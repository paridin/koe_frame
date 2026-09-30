defmodule Defdo.KoeFrame.MediaIntake.Staging do
  @moduledoc """
  Local, server-owned storage for resumable media uploads.

  Temporary objects are named only by tenant and upload UUID. A validated
  relative path is used only when a verified object is moved into its intake
  directory. File ownership is configured for the NAS media service account;
  the caller never supplies an owner, mode, or absolute path.
  """

  import Bitwise, only: [band: 2]

  alias Defdo.KoeFrame.MediaIntake.{Digest, FilesystemAdapter, PathSafety, RelativePath, Upload}
  alias Defdo.Tenant.Context

  @max_chunk_bytes 8 * 1024 * 1024
  @partial_file_mode 0o600
  @storage_root_mode 0o750
  @private_directory_mode 0o700

  @spec prepare_session(Upload.t()) :: :ok | {:error, term()}
  def prepare_session(%Upload{} = upload) do
    base = Path.join(root!(), "uploads")

    with :ok <- ensure_tenant_scope(upload),
         {:ok, path} <- session_path(upload),
         :ok <- ensure_storage_root(),
         {:ok, _base} <- ensure_directory(base, @private_directory_mode),
         {:ok, _dir} <- ensure_directory(session_directory(upload), @private_directory_mode),
         :ok <- create_partial_file(path, upload.upload_offset),
         :ok <- sync_file(path),
         :ok <- sync_directory(Path.dirname(path)) do
      :ok
    end
  end

  @spec append_chunk(Upload.t(), non_neg_integer(), binary()) :: :ok | {:error, term()}
  def append_chunk(%Upload{} = upload, offset, chunk)
      when is_integer(offset) and offset >= 0 and is_binary(chunk) do
    cond do
      byte_size(chunk) == 0 ->
        {:error, :empty_chunk}

      byte_size(chunk) > @max_chunk_bytes ->
        {:error, :chunk_too_large}

      true ->
        with :ok <- ensure_tenant_scope(upload),
             {:ok, path} <- session_path(upload),
             :ok <- prepare_session(upload),
             :ok <- append_at(path, offset, chunk) do
          :ok
        end
    end
  end

  @spec staged_path(Upload.t()) :: {:ok, String.t()} | {:error, term()}
  def staged_path(%Upload{} = upload) do
    with :ok <- ensure_tenant_scope(upload),
         {:ok, relative_path} <- RelativePath.validate(upload.relative_path),
         :ok <- validate_uuid(upload.tenant_id),
         :ok <- validate_uuid(upload.intake_id) do
      intake_root = Path.join([root!(), "intakes", upload.tenant_id, upload.intake_id])
      destination = Path.expand(relative_path, intake_root)

      if String.starts_with?(destination, Path.expand(intake_root) <> "/"),
        do: {:ok, destination},
        else: {:error, :invalid_relative_path}
    end
  end

  @spec finalize(Upload.t()) :: :ok | {:error, term()}
  def finalize(%Upload{} = upload) do
    with :ok <- ensure_tenant_scope(upload),
         :ok <- ensure_storage_root(),
         {:ok, source_path} <- session_path(upload),
         {:ok, object_key} <- object_key(upload) do
      case storage_adapter().upload(source_path, object_key, storage_config(),
             expected_sha256: upload.expected_sha256
           ) do
        {:ok, _stored} -> :ok
        {:error, reason} -> {:error, reason}
      end
    end
  end

  @spec remove_session(Upload.t()) :: :ok | {:error, term()}
  def remove_session(%Upload{} = upload) do
    with :ok <- ensure_tenant_scope(upload),
         {:ok, path} <- session_path(upload) do
      case File.rm(path) do
        :ok -> sync_directory(Path.dirname(path))
        {:error, :enoent} -> :ok
        error -> error
      end
    end
  end

  @spec verify_staged(Upload.t()) :: :ok | {:error, term()}
  def verify_staged(%Upload{} = upload) do
    with :ok <- ensure_tenant_scope(upload),
         :ok <- ensure_storage_root(),
         {:ok, destination} <- staged_path(upload),
         :ok <- validate_staged_directories(destination),
         {:ok, %{type: :regular}} <- File.lstat(destination),
         {:ok, digest} <- Digest.sha256(destination),
         true <- digest == upload.expected_sha256 or {:error, :checksum_mismatch} do
      :ok
    else
      {:ok, _info} -> {:error, :unsafe_staged_destination}
      {:error, :enoent} -> {:error, :staged_file_missing}
      {:error, reason} -> {:error, reason}
      false -> {:error, :checksum_mismatch}
    end
  end

  defp validate_staged_directories(destination) do
    intake_root = Path.join(root!(), "intakes")

    case File.lstat(intake_root) do
      {:ok, %{type: :directory}} ->
        destination
        |> Path.dirname()
        |> Path.relative_to(intake_root)
        |> Path.split()
        |> Enum.reject(&(&1 in [".", ""]))
        |> Enum.reduce_while(intake_root, fn segment, parent ->
          path = Path.join(parent, segment)

          case File.lstat(path) do
            {:ok, %{type: :directory}} -> {:cont, path}
            {:ok, _info} -> {:halt, {:error, :unsafe_staged_directory}}
            {:error, reason} -> {:halt, {:error, reason}}
          end
        end)
        |> case do
          {:error, reason} -> {:error, reason}
          _path -> :ok
        end

      {:ok, _info} ->
        {:error, :unsafe_staged_directory}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp append_at(path, offset, chunk) do
    with {:ok, info} <- File.lstat(path),
         true <- info.type == :regular or {:error, :unsafe_staging_file},
         {:ok, io} <- File.open(path, [:read, :write, :binary]) do
      try do
        with {:ok, actual_size} <- :file.position(io, :eof),
             true <- actual_size >= offset or {:error, :staging_data_lost},
             {:ok, ^offset} <- :file.position(io, offset),
             :ok <- :file.truncate(io),
             :ok <- :file.write(io, chunk),
             :ok <- :file.sync(io) do
          :ok
        else
          {:ok, actual_offset} when actual_offset != offset -> {:error, :staging_seek_failed}
          false -> {:error, :unsafe_staging_file}
          {:error, reason} -> {:error, reason}
        end
      after
        File.close(io)
      end
    else
      false -> {:error, :unsafe_staging_file}
      {:error, reason} -> {:error, reason}
    end
  end

  defp create_partial_file(path, committed_offset) do
    case File.lstat(path) do
      {:ok, %{type: :regular}} -> File.chmod(path, @partial_file_mode)
      {:ok, _info} -> {:error, :unsafe_staging_file}
      {:error, :enoent} when committed_offset == 0 -> create_exclusive_file(path)
      {:error, :enoent} -> {:error, :staging_data_lost}
      {:error, reason} -> {:error, reason}
    end
  end

  defp create_exclusive_file(path) do
    case File.open(path, [:write, :binary, :exclusive]) do
      {:ok, io} ->
        result = :file.sync(io)
        File.close(io)

        with :ok <- result,
             :ok <- File.chmod(path, @partial_file_mode) do
          :ok
        end

      {:error, :eexist} ->
        create_partial_file(path, 0)

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp ensure_directory(path, mode) do
    with :ok <- File.mkdir_p(path),
         {:ok, %{type: :directory}} <- File.lstat(path),
         :ok <- File.chmod(path, mode),
         :ok <- sync_directory(path),
         :ok <- sync_directory(Path.dirname(path)) do
      {:ok, path}
    else
      {:ok, _info} -> {:error, :unsafe_staging_directory}
      {:error, reason} -> {:error, reason}
    end
  end

  defp object_key(upload) do
    {:ok, Path.join([upload.tenant_id, upload.intake_id, upload.relative_path])}
  end

  defp storage_adapter do
    Application.get_env(:koe_frame, :media_storage_adapter, FilesystemAdapter)
  end

  defp storage_config do
    %{
      root: Path.join(root!(), "intakes"),
      owner: Application.get_env(:koe_frame, :media_staging_owner),
      file_mode: 0o640,
      directory_mode: 0o750
    }
  end

  defp session_directory(upload) do
    Path.join([root!(), "uploads", upload.tenant_id])
  end

  defp session_path(upload) do
    with :ok <- validate_uuid(upload.tenant_id),
         :ok <- validate_uuid(upload.id) do
      {:ok, Path.join([session_directory(upload), upload.id <> ".part"])}
    end
  end

  defp validate_uuid(value) do
    case Ecto.UUID.cast(value) do
      {:ok, _uuid} -> :ok
      :error -> {:error, :invalid_upload_identifier}
    end
  end

  defp ensure_storage_root do
    root = root!()

    with :ok <- PathSafety.validate_root_parent(root) do
      case File.lstat(root) do
        {:ok, %{type: :directory}} ->
          validate_existing_storage_root(root)

        {:ok, _info} ->
          {:error, :unsafe_staging_root}

        {:error, :enoent} ->
          case File.mkdir(root) do
            :ok -> finish_storage_root(root)
            {:error, :eexist} -> validate_existing_storage_root(root)
            {:error, reason} -> {:error, reason}
          end

        {:error, reason} ->
          {:error, reason}
      end
    end
  end

  defp finish_storage_root(root) do
    with :ok <- File.chmod(root, @storage_root_mode),
         :ok <- apply_storage_group(root),
         :ok <- sync_directory(root),
         :ok <- sync_directory(Path.dirname(root)) do
      :ok
    end
  end

  defp validate_existing_storage_root(root) do
    expected_gid =
      case Application.get_env(:koe_frame, :media_staging_owner) do
        {_uid, gid} when is_integer(gid) and gid >= 0 -> gid
        nil -> nil
        _invalid -> :invalid
      end

    case File.lstat(root) do
      {:ok, %{type: :directory, mode: mode, gid: gid}}
      when band(mode, 0o777) == @storage_root_mode and expected_gid != :invalid ->
        if is_nil(expected_gid) or gid == expected_gid,
          do: :ok,
          else: {:error, :unsafe_staging_root}

      {:ok, _info} ->
        {:error, :unsafe_staging_root}

      {:error, reason} ->
        {:error, {:storage_root_unavailable, reason}}
    end
  end

  defp apply_storage_group(path) do
    case Application.get_env(:koe_frame, :media_staging_owner) do
      {_uid, gid} when is_integer(gid) and gid >= 0 ->
        with {:ok, %{type: :directory, uid: uid}} <- File.lstat(path),
             :ok <- change_group(path, uid, gid) do
          :ok
        else
          {:ok, _info} -> {:error, :unsafe_staging_directory}
          {:error, reason} -> {:error, {:ownership_failed, reason}}
        end

      nil ->
        :ok

      _invalid ->
        {:error, :invalid_staging_owner}
    end
  end

  defp change_group(path, uid, gid) do
    case :file.change_owner(String.to_charlist(path), uid, gid) do
      :ok -> :ok
      {:error, reason} -> {:error, {:ownership_failed, reason}}
    end
  end

  defp sync_file(path) do
    case File.open(path, [:read, :raw], &:file.sync/1) do
      :ok -> :ok
      {:ok, :ok} -> :ok
      {:ok, {:error, reason}} -> {:error, {:file_sync_failed, reason}}
      {:error, reason} -> {:error, {:file_sync_failed, reason}}
    end
  end

  defp sync_directory(path) do
    case File.open(path, [:read, :raw, :directory], &:file.sync/1) do
      :ok -> :ok
      {:ok, :ok} -> :ok
      {:ok, {:error, reason}} -> {:error, {:directory_sync_failed, reason}}
      {:error, reason} -> {:error, {:directory_sync_failed, reason}}
    end
  end

  defp root! do
    root = Application.fetch_env!(:koe_frame, :media_staging_root)

    if Path.type(root) == :absolute do
      Path.expand(root)
    else
      raise ArgumentError, ":media_staging_root must be an absolute path"
    end
  end

  defp ensure_tenant_scope(%Upload{tenant_id: upload_tenant_id}) do
    case Context.tenant_id() do
      tenant_id when is_binary(tenant_id) and tenant_id != "" ->
        if tenant_id == upload_tenant_id,
          do: :ok,
          else: {:error, :tenant_context_mismatch}

      _missing_tenant ->
        {:error, :missing_tenant_context}
    end
  end
end
