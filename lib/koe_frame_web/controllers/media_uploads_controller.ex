defmodule Defdo.KoeFrameWeb.MediaUploadsController do
  @moduledoc "Authenticated Tus endpoints for KoeFrame media intake uploads."

  use Defdo.KoeFrameWeb, :controller

  alias Defdo.KoeFrame.MediaIntake.Uploads
  alias Defdo.Tenant.Context

  @tus_version "1.0.0"
  @max_chunk_bytes 8 * 1024 * 1024
  @read_length 64 * 1024
  @metadata_keys ["relative_path", "sha256"]

  def options(conn, _params) do
    conn
    |> put_resp_header("tus-version", @tus_version)
    |> put_resp_header("tus-extension", "creation")
    |> put_resp_header("cache-control", "no-store")
    |> send_resp(204, "")
  end

  def create(conn, %{"intake_id" => intake_id}) do
    with :ok <- require_tus_version(conn),
         {:ok, length} <- request_upload_length(conn),
         {:ok, metadata} <- request_metadata(conn),
         {:ok, upload} <- create_session(conn, intake_id, length, metadata) do
      conn
      |> tus_headers()
      |> put_resp_header("location", upload_location(upload.id))
      |> put_resp_header("upload-length", Integer.to_string(upload.upload_length))
      |> put_resp_header("upload-offset", Integer.to_string(upload.upload_offset))
      |> send_resp(201, "")
    else
      {:error, :unsupported_tus_version} -> tus_error(conn, 412, "unsupported_tus_version")
      {:error, :invalid_intake_id} -> tus_error(conn, 400, "invalid_intake_id")
      {:error, :invalid_upload_length} -> tus_error(conn, 400, "invalid_upload_length")
      {:error, :invalid_upload_metadata} -> tus_error(conn, 400, "invalid_upload_metadata")
      {:error, :upload_idempotency_conflict} -> tus_error(conn, 409, "upload_conflict")
      {:error, {:invalid_upload, _changeset}} -> tus_error(conn, 422, "invalid_upload")
      {:error, _reason} -> tus_error(conn, 500, "upload_failed")
    end
  end

  def create(conn, _params), do: tus_error(conn, 400, "invalid_intake_id")

  def head(conn, %{"id" => id}) do
    with :ok <- require_tus_version(conn),
         {:ok, upload} <- get_upload(conn, id) do
      conn
      |> tus_headers()
      |> put_resp_header("cache-control", "no-store")
      |> put_resp_header("upload-length", Integer.to_string(upload.upload_length))
      |> put_resp_header("upload-offset", Integer.to_string(upload.upload_offset))
      |> send_resp(200, "")
    else
      {:error, :unsupported_tus_version} ->
        tus_error(conn, 412, "unsupported_tus_version")

      {:error, reason} when reason in [:not_found, :invalid_upload_identifier] ->
        tus_error(conn, 404, "upload_not_found")

      {:error, _reason} ->
        tus_error(conn, 500, "upload_lookup_failed")
    end
  end

  def patch(conn, %{"id" => id}) do
    with :ok <- require_tus_version(conn),
         {:ok, offset} <- request_offset(conn),
         :ok <- require_chunk_content_type(conn),
         {:ok, chunk, conn} <- read_chunk(conn),
         {:ok, upload} <- append_chunk(conn, id, offset, chunk) do
      conn
      |> tus_headers()
      |> put_resp_header("upload-offset", Integer.to_string(upload.upload_offset))
      |> send_resp(204, "")
    else
      {:error, :unsupported_tus_version} ->
        tus_error(conn, 412, "unsupported_tus_version")

      {:error, :invalid_upload_offset} ->
        tus_error(conn, 400, "invalid_upload_offset")

      {:error, :invalid_content_type} ->
        tus_error(conn, 415, "invalid_content_type")

      {:error, :empty_chunk} ->
        tus_error(conn, 400, "empty_chunk")

      {:error, :chunk_too_large} ->
        tus_error(conn, 413, "chunk_too_large")

      {:error, :chunk_exceeds_upload_length} ->
        tus_error(conn, 413, "chunk_exceeds_upload_length")

      {:error, :invalid_chunk} ->
        tus_error(conn, 400, "invalid_chunk")

      {:error, {:offset_mismatch, current_offset}} ->
        conn
        |> tus_headers()
        |> put_resp_header("upload-offset", Integer.to_string(current_offset))
        |> tus_error(409, "offset_mismatch")

      {:error, {:upload_not_writable, _status}} ->
        tus_error(conn, 409, "upload_not_writable")

      {:error, reason} when reason in [:not_found, :invalid_upload_identifier] ->
        tus_error(conn, 404, "upload_not_found")

      {:error, _reason} ->
        tus_error(conn, 500, "upload_write_failed")
    end
  end

  def finalize(conn, %{"id" => id}) do
    with :ok <- require_tus_version(conn),
         {:ok, upload} <- finalize_upload(conn, id) do
      conn
      |> tus_headers()
      |> put_resp_header("upload-offset", Integer.to_string(upload.upload_offset))
      |> put_status(:ok)
      |> json(%{id: upload.id, status: "staged"})
    else
      {:error, :unsupported_tus_version} ->
        tus_error(conn, 412, "unsupported_tus_version")

      {:error, {:upload_incomplete, _offset, _length}} ->
        tus_error(conn, 409, "upload_incomplete")

      {:error, :checksum_mismatch} ->
        tus_error(conn, 422, "checksum_mismatch")

      {:error, {:upload_not_finalizable, _status}} ->
        tus_error(conn, 409, "upload_not_finalizable")

      {:error, reason} when reason in [:not_found, :invalid_upload_identifier] ->
        tus_error(conn, 404, "upload_not_found")

      {:error, _reason} ->
        tus_error(conn, 500, "upload_finalize_failed")
    end
  end

  defp create_session(conn, intake_id, length, metadata) do
    with {:ok, intake_uuid} <- Ecto.UUID.cast(intake_id) do
      with_tenant(conn, fn ->
        Uploads.create_upload(%{
          intake_id: intake_uuid,
          relative_path: metadata["relative_path"],
          upload_length: length,
          expected_sha256: metadata["sha256"]
        })
      end)
    else
      :error -> {:error, :invalid_intake_id}
    end
  end

  defp get_upload(conn, id) do
    with_tenant(conn, fn ->
      case Uploads.get_upload(id) do
        {:ok, %{} = upload} -> {:ok, upload}
        {:ok, nil} -> {:error, :not_found}
        {:error, reason} -> {:error, reason}
      end
    end)
  end

  defp append_chunk(conn, id, offset, chunk) do
    with_tenant(conn, fn -> Uploads.append_chunk(id, offset, chunk) end)
  end

  defp finalize_upload(conn, id) do
    with_tenant(conn, fn -> Uploads.finalize_upload(id) end)
  end

  defp with_tenant(conn, fun) do
    case conn.assigns[:media_tenant_id] do
      tenant_id when is_binary(tenant_id) -> Context.with_context(tenant_id, fun)
      _ -> {:error, :missing_authenticated_tenant}
    end
  end

  defp require_tus_version(conn) do
    case get_req_header(conn, "tus-resumable") do
      [@tus_version] -> :ok
      _ -> {:error, :unsupported_tus_version}
    end
  end

  defp request_upload_length(conn) do
    case get_req_header(conn, "upload-length") do
      [value] ->
        parse_non_negative_integer(value, :invalid_upload_length)

      _ ->
        {:error, :invalid_upload_length}
    end
  end

  defp request_offset(conn) do
    case get_req_header(conn, "upload-offset") do
      [value] ->
        parse_non_negative_integer(value, :invalid_upload_offset)

      _ ->
        {:error, :invalid_upload_offset}
    end
  end

  defp parse_non_negative_integer(value, error) do
    if Regex.match?(~r/\A[0-9]+\z/, value) do
      {integer, ""} = Integer.parse(value)
      {:ok, integer}
    else
      {:error, error}
    end
  end

  defp request_metadata(conn) do
    case get_req_header(conn, "upload-metadata") do
      [value] -> decode_metadata(value)
      _ -> {:error, :invalid_upload_metadata}
    end
  end

  defp decode_metadata(value) do
    with {:ok, entries} <- decode_metadata_entries(String.split(value, ",", trim: false)),
         true <- Enum.sort(Map.keys(entries)) == Enum.sort(@metadata_keys) do
      {:ok, entries}
    else
      _ -> {:error, :invalid_upload_metadata}
    end
  end

  defp decode_metadata_entries(entries) do
    Enum.reduce_while(entries, {:ok, %{}}, fn entry, {:ok, acc} ->
      case String.split(String.trim(entry), " ", parts: 2) do
        [key, encoded] when key in @metadata_keys ->
          with false <- Map.has_key?(acc, key),
               {:ok, decoded} <- Base.decode64(encoded),
               true <- String.valid?(decoded) do
            {:cont, {:ok, Map.put(acc, key, decoded)}}
          else
            _ -> {:halt, {:error, :invalid_upload_metadata}}
          end

        _ ->
          {:halt, {:error, :invalid_upload_metadata}}
      end
    end)
  end

  defp require_chunk_content_type(conn) do
    case get_req_header(conn, "content-type") do
      ["application/offset+octet-stream"] -> :ok
      _ -> {:error, :invalid_content_type}
    end
  end

  defp read_chunk(conn), do: read_chunk(conn, [], 0)

  defp read_chunk(conn, acc, size) do
    case Plug.Conn.read_body(conn, length: @max_chunk_bytes + 1, read_length: @read_length) do
      {:ok, body, conn} ->
        finish_chunk(conn, acc, size, body)

      {:more, body, conn} ->
        if size + byte_size(body) > @max_chunk_bytes do
          {:error, :chunk_too_large}
        else
          read_chunk(conn, [acc, body], size + byte_size(body))
        end

      {:error, _reason} ->
        {:error, :invalid_chunk}
    end
  end

  defp finish_chunk(conn, acc, size, body) do
    total = size + byte_size(body)

    cond do
      total == 0 -> {:error, :empty_chunk}
      total > @max_chunk_bytes -> {:error, :chunk_too_large}
      true -> {:ok, IO.iodata_to_binary([acc, body]), conn}
    end
  end

  defp upload_location(id), do: "/api/v1/media/uploads/#{id}"

  defp tus_headers(conn) do
    conn
    |> put_resp_header("tus-resumable", @tus_version)
    |> put_resp_header("tus-version", @tus_version)
    |> put_resp_header("cache-control", "no-store")
  end

  defp tus_error(conn, status, code) do
    conn
    |> tus_headers()
    |> put_status(status)
    |> json(%{errors: %{code: code}})
  end
end
