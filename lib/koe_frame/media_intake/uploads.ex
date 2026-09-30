defmodule Defdo.KoeFrame.MediaIntake.Uploads do
  @moduledoc """
  Tenant-scoped lifecycle for resumable, single-file uploads.

  The HTTP/authentication edge is intentionally separate. Callers must first
  establish `Defdo.Tenant.Context`; this module refuses to create or look up
  upload records without it.
  """

  import Ecto.Query

  alias Defdo.KoeFrame.MediaIntake.{Staging, Upload}
  alias Defdo.KoeFrame.Repo
  alias Defdo.Tenant.Context

  @spec create_upload(map()) :: {:ok, Upload.t()} | {:error, term()}
  def create_upload(attrs) when is_map(attrs) do
    with :ok <- require_tenant_context() do
      case Repo.transaction(fn ->
             create_or_return_upload(attrs)
           end) do
        {:ok, %Upload{} = upload} -> {:ok, upload}
        {:error, reason} -> {:error, reason}
      end
    end
  end

  def create_upload(_attrs), do: {:error, :invalid_upload_attributes}

  @spec get_upload(Ecto.UUID.t()) :: {:ok, Upload.t() | nil} | {:error, term()}
  def get_upload(id) do
    with :ok <- require_tenant_context(),
         {:ok, uuid} <- cast_uuid(id) do
      {:ok, Repo.get(Upload, uuid)}
    end
  end

  @spec list_intake_uploads(Ecto.UUID.t()) :: {:ok, [Upload.t()]} | {:error, term()}
  def list_intake_uploads(intake_id) do
    with :ok <- require_tenant_context(),
         {:ok, uuid} <- cast_uuid(intake_id) do
      uploads =
        from(upload in Upload,
          where: upload.intake_id == ^uuid,
          order_by: [asc: upload.relative_path, asc: upload.id]
        )
        |> Repo.all()

      {:ok, uploads}
    end
  end

  @spec append_chunk(Ecto.UUID.t(), non_neg_integer(), binary()) ::
          {:ok, Upload.t()} | {:error, term()}
  def append_chunk(id, offset, chunk)
      when is_integer(offset) and offset >= 0 and is_binary(chunk) do
    with :ok <- require_tenant_context(),
         {:ok, uuid} <- cast_uuid(id),
         :ok <- validate_chunk(chunk) do
      case Repo.transaction(fn ->
             upload = locked_upload!(uuid)
             append_to_upload(upload, offset, chunk)
           end) do
        {:ok, %Upload{} = upload} -> {:ok, upload}
        {:error, reason} -> {:error, reason}
      end
    end
  end

  def append_chunk(_id, _offset, _chunk), do: {:error, :invalid_chunk}

  @spec finalize_upload(Ecto.UUID.t()) :: {:ok, Upload.t()} | {:error, term()}
  def finalize_upload(id) do
    with :ok <- require_tenant_context(),
         {:ok, uuid} <- cast_uuid(id) do
      case Repo.transaction(fn ->
             upload = locked_upload!(uuid)
             finalize_locked_upload(upload)
           end) do
        {:ok, %Upload{} = upload} -> {:ok, upload}
        {:ok, {:error, reason}} -> {:error, reason}
        {:error, reason} -> {:error, reason}
      end
    end
  end

  defp create_or_return_upload(attrs) do
    changeset = Upload.changeset(%Upload{}, attrs)

    case Repo.insert(changeset,
           on_conflict: :nothing,
           conflict_target: [:tenant_id, :intake_id, :relative_path],
           returning: true
         ) do
      {:ok, _inserted_or_conflicted} ->
        key = %{
          intake_id: Ecto.Changeset.get_field(changeset, :intake_id),
          relative_path: Ecto.Changeset.get_field(changeset, :relative_path)
        }

        case Repo.get_by(Upload, key) do
          %Upload{} = upload -> return_existing(upload, changeset)
          nil -> Repo.rollback(:upload_insert_not_visible)
        end

      {:error, changeset} ->
        Repo.rollback({:invalid_upload, changeset})
    end
  end

  defp return_existing(upload, changeset) do
    expected_size = Ecto.Changeset.get_field(changeset, :upload_length)
    expected_digest = Ecto.Changeset.get_field(changeset, :expected_sha256)

    if upload.upload_length == expected_size and upload.expected_sha256 == expected_digest do
      case upload.status do
        :uploading ->
          case Staging.prepare_session(upload) do
            :ok -> upload
            {:error, reason} -> Repo.rollback({:staging_prepare_failed, reason})
          end

        :staged ->
          case Staging.verify_staged(upload) do
            :ok -> upload
            {:error, reason} -> Repo.rollback({:staged_file_check_failed, reason})
          end

        _terminal ->
          upload
      end
    else
      Repo.rollback(:upload_idempotency_conflict)
    end
  end

  defp append_to_upload(%Upload{status: :uploading} = upload, offset, chunk) do
    cond do
      offset != upload.upload_offset ->
        Repo.rollback({:offset_mismatch, upload.upload_offset})

      byte_size(chunk) > upload.upload_length - upload.upload_offset ->
        Repo.rollback(:chunk_exceeds_upload_length)

      true ->
        case Staging.append_chunk(upload, offset, chunk) do
          :ok ->
            upload
            |> Ecto.Changeset.change(upload_offset: offset + byte_size(chunk))
            |> Repo.update!()

          {:error, reason} ->
            Repo.rollback({:staging_append_failed, reason})
        end
    end
  end

  defp append_to_upload(%Upload{status: status}, _offset, _chunk),
    do: Repo.rollback({:upload_not_writable, status})

  defp finalize_locked_upload(%Upload{status: :staged} = upload) do
    case Staging.verify_staged(upload) do
      :ok -> upload
      {:error, reason} -> Repo.rollback({:staged_file_check_failed, reason})
    end
  end

  defp finalize_locked_upload(%Upload{status: :uploading} = upload) do
    if upload.upload_offset == upload.upload_length do
      case Staging.finalize(upload) do
        :ok ->
          upload
          |> Ecto.Changeset.change(status: :staged)
          |> Repo.update!()

        {:error, :checksum_mismatch} ->
          upload
          |> Ecto.Changeset.change(status: :checksum_mismatch)
          |> Repo.update!()

          case Staging.remove_session(upload) do
            :ok -> {:error, :checksum_mismatch}
            {:error, reason} -> {:error, {:checksum_mismatch_cleanup_failed, reason}}
          end

        {:error, reason} ->
          Repo.rollback({:staging_finalize_failed, reason})
      end
    else
      Repo.rollback({:upload_incomplete, upload.upload_offset, upload.upload_length})
    end
  end

  defp finalize_locked_upload(%Upload{status: status}),
    do: Repo.rollback({:upload_not_finalizable, status})

  defp locked_upload!(uuid) do
    case from(upload in Upload, where: upload.id == ^uuid, lock: "FOR UPDATE") |> Repo.one() do
      %Upload{} = upload -> upload
      nil -> Repo.rollback(:not_found)
    end
  end

  defp validate_chunk(chunk) do
    cond do
      byte_size(chunk) == 0 -> {:error, :empty_chunk}
      byte_size(chunk) > 8 * 1024 * 1024 -> {:error, :chunk_too_large}
      true -> :ok
    end
  end

  defp require_tenant_context do
    if is_binary(Context.tenant_id()) and Context.tenant_id() != "",
      do: :ok,
      else: {:error, :missing_tenant_context}
  end

  defp cast_uuid(value) do
    case Ecto.UUID.cast(value) do
      {:ok, uuid} -> {:ok, uuid}
      :error -> {:error, :invalid_upload_identifier}
    end
  end
end
