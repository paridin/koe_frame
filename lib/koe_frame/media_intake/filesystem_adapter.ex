defmodule Defdo.KoeFrame.MediaIntake.FilesystemAdapter do
  @moduledoc """
  Publishes verified intake files into KoeFrame's configured local media tree.

  This is KoeFrame's host adapter for `Defdo.Uploader.Adapter`. The reusable
  upload/storage contract comes from `defdo_uploader`; NAS layout, ownership,
  and permissions come from KoeFrame's server configuration.
  """

  @behaviour Defdo.Uploader.Adapter

  import Bitwise, only: [band: 2]

  alias Defdo.KoeFrame.MediaIntake.{Digest, PathSafety, RelativePath}

  @file_mode 0o640
  @directory_mode 0o750

  @impl true
  def upload(source_path, object_key, %{root: root} = config, opts) do
    with {:ok, destination} <- target_path(root, object_key),
         :ok <- ensure_root(root, config),
         :ok <-
           publish_verified_file(
             source_path,
             destination,
             opts[:expected_sha256],
             root,
             config
           ) do
      {:ok,
       %{
         url: file_url(destination),
         object_key: object_key,
         bucket: nil,
         endpoint: nil
       }}
    end
  end

  def upload(_source_path, _object_key, _config, _opts), do: {:error, :invalid_filesystem_config}

  @impl true
  def head(object_key, %{root: root} = config, _opts) do
    with {:ok, path} <- target_path(root, object_key),
         :ok <- ensure_root(root, config),
         :ok <- validate_parent_directories(root, path) do
      case File.lstat(path) do
        {:ok, %{type: :regular, size: size}} ->
          {:ok,
           %{
             content_length: size,
             content_type: nil,
             etag: nil,
             last_modified: nil
           }}

        {:ok, _info} ->
          {:error, :unsafe_staged_destination}

        {:error, reason} ->
          {:error, reason}
      end
    end
  end

  def head(_object_key, _config, _opts), do: {:error, :invalid_filesystem_config}

  @impl true
  def delete(object_key, %{root: root} = config, _opts) do
    with {:ok, path} <- target_path(root, object_key),
         :ok <- ensure_root(root, config),
         :ok <- validate_parent_directories(root, path) do
      case File.lstat(path) do
        {:ok, %{type: :regular}} ->
          with :ok <- File.rm(path),
               :ok <- sync_directory(Path.dirname(path)) do
            :ok
          end

        {:ok, _info} ->
          {:error, :unsafe_staged_destination}

        {:error, :enoent} ->
          :ok

        {:error, reason} ->
          {:error, reason}
      end
    else
      {:error, reason} -> {:error, reason}
    end
  end

  def delete(_object_key, _config, _opts), do: {:error, :invalid_filesystem_config}

  @impl true
  def public_url(_bucket, object_key, %{root: root} = config, _opts) do
    with {:ok, path} <- target_path(root, object_key),
         :ok <- ensure_root(root, config),
         :ok <- validate_parent_directories(root, path),
         {:ok, %{type: :regular}} <- File.lstat(path) do
      file_url(path)
    else
      {:error, reason} ->
        raise ArgumentError,
              "cannot build a filesystem URL for the media object: #{inspect(reason)}"

      {:ok, _info} ->
        raise ArgumentError, "cannot build a filesystem URL for a non-file media object"
    end
  end

  defp publish_verified_file(source_path, destination, expected_sha256, root, config) do
    case File.lstat(source_path) do
      {:ok, %{type: :regular}} ->
        with :ok <- verify_digest(source_path, expected_sha256),
             :ok <- ensure_parent_directories(root, destination, config),
             :ok <- link_staged_file(source_path, destination, expected_sha256, config) do
          :ok
        end

      {:error, :enoent} ->
        with :ok <- ensure_parent_directories(root, destination, config) do
          recover_linked_file(destination, expected_sha256, config)
        end

      {:ok, _info} ->
        {:error, :unsafe_staging_file}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp link_staged_file(source_path, destination, expected_sha256, config) do
    case File.lstat(destination) do
      {:error, :enoent} ->
        case File.ln(source_path, destination) do
          :ok ->
            finish_staged_link(source_path, destination, config)

          {:error, :eexist} ->
            verify_existing_link(source_path, destination, expected_sha256, config)

          {:error, reason} ->
            {:error, {:staging_link_failed, reason}}
        end

      {:ok, %{type: :regular}} ->
        verify_existing_link(source_path, destination, expected_sha256, config)

      {:ok, _info} ->
        {:error, :unsafe_staged_destination}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp verify_existing_link(source_path, destination, expected_sha256, config) do
    with :ok <- verify_digest(destination, expected_sha256) do
      finish_staged_link(source_path, destination, config)
    else
      {:error, :checksum_mismatch} -> {:error, :destination_exists}
      {:error, reason} -> {:error, reason}
    end
  end

  defp finish_staged_link(source_path, destination, config) do
    with :ok <- File.chmod(destination, Map.get(config, :file_mode, @file_mode)),
         :ok <- apply_owner(destination, config),
         :ok <- sync_file(destination),
         :ok <- sync_directory(Path.dirname(destination)) do
      case File.rm(source_path) do
        :ok -> sync_directory(Path.dirname(source_path))
        {:error, :enoent} -> :ok
        {:error, reason} -> {:error, {:staging_cleanup_failed, reason}}
      end
    end
  end

  defp recover_linked_file(destination, expected_sha256, config) do
    with {:ok, %{type: :regular}} <- File.lstat(destination),
         :ok <- verify_digest(destination, expected_sha256),
         :ok <- File.chmod(destination, Map.get(config, :file_mode, @file_mode)),
         :ok <- apply_owner(destination, config),
         :ok <- sync_file(destination),
         :ok <- sync_directory(Path.dirname(destination)) do
      :ok
    else
      {:ok, _info} -> {:error, :unsafe_staged_destination}
      {:error, :enoent} -> {:error, :staging_file_missing}
      {:error, reason} -> {:error, reason}
    end
  end

  defp verify_digest(path, expected_sha256) when is_binary(expected_sha256) do
    with true <-
           Regex.match?(~r/\A[0-9a-f]{64}\z/, expected_sha256) or
             {:error, :invalid_expected_digest},
         {:ok, ^expected_sha256} <- Digest.sha256(path) do
      :ok
    else
      false -> {:error, :invalid_expected_digest}
      {:ok, _digest} -> {:error, :checksum_mismatch}
      {:error, reason} -> {:error, reason}
    end
  end

  defp verify_digest(_path, _expected_sha256), do: {:error, :invalid_expected_digest}

  defp target_path(root, object_key) when is_binary(root) and is_binary(object_key) do
    with true <- Path.type(root) == :absolute or {:error, :filesystem_root_must_be_absolute},
         {:ok, validated_key} <- RelativePath.validate(object_key) do
      root = Path.expand(root)
      path = Path.expand(validated_key, root)

      if String.starts_with?(path, root <> "/"),
        do: {:ok, path},
        else: {:error, :invalid_object_key}
    else
      false -> {:error, :filesystem_root_must_be_absolute}
      {:error, reason} -> {:error, reason}
    end
  end

  defp target_path(_root, _object_key), do: {:error, :invalid_filesystem_config}

  defp ensure_root(root, config) do
    with :ok <- PathSafety.validate_root_parent(root) do
      case File.lstat(root) do
        {:ok, %{type: :directory}} ->
          validate_existing_root(root, config)

        {:ok, _info} ->
          {:error, :unsafe_filesystem_root}

        {:error, :enoent} ->
          case File.mkdir(root) do
            :ok -> finish_directory(root, config)
            {:error, :eexist} -> validate_existing_root(root, config)
            {:error, reason} -> {:error, reason}
          end

        {:error, reason} ->
          {:error, reason}
      end
    end
  end

  defp validate_existing_root(root, config) do
    expected_mode = Map.get(config, :directory_mode, @directory_mode)

    expected_gid =
      case Map.get(config, :owner) do
        {_uid, gid} when is_integer(gid) and gid >= 0 -> gid
        nil -> nil
        _invalid -> :invalid
      end

    case File.lstat(root) do
      {:ok, %{type: :directory, mode: mode, gid: gid}}
      when band(mode, 0o777) == expected_mode and expected_gid != :invalid ->
        if is_nil(expected_gid) or gid == expected_gid,
          do: :ok,
          else: {:error, :unsafe_filesystem_root}

      {:ok, _info} ->
        {:error, :unsafe_filesystem_root}

      {:error, reason} ->
        {:error, {:filesystem_root_unavailable, reason}}
    end
  end

  defp ensure_parent_directories(root, destination, config) do
    relative = Path.relative_to(Path.dirname(destination), Path.expand(root))

    relative
    |> Path.split()
    |> Enum.reject(&(&1 in [".", ""]))
    |> Enum.reduce_while(Path.expand(root), fn segment, parent ->
      path = Path.join(parent, segment)

      case ensure_directory(path, config) do
        :ok -> {:cont, path}
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
    |> case do
      {:error, reason} -> {:error, reason}
      _path -> :ok
    end
  end

  defp validate_parent_directories(root, destination) do
    relative = Path.relative_to(Path.dirname(destination), Path.expand(root))

    relative
    |> Path.split()
    |> Enum.reject(&(&1 in [".", ""]))
    |> Enum.reduce_while(Path.expand(root), fn segment, parent ->
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
  end

  defp ensure_directory(path, config) do
    case File.mkdir(path) do
      :ok ->
        finish_directory(path, config)

      {:error, :eexist} ->
        case File.lstat(path) do
          {:ok, %{type: :directory}} -> finish_directory(path, config)
          {:ok, _info} -> {:error, :unsafe_staged_directory}
          {:error, reason} -> {:error, reason}
        end

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp finish_directory(path, config) do
    with :ok <- File.chmod(path, Map.get(config, :directory_mode, @directory_mode)),
         :ok <- apply_group(path, config),
         :ok <- sync_directory(path),
         :ok <- sync_directory(Path.dirname(path)) do
      :ok
    end
  end

  defp apply_group(path, config) do
    case Map.get(config, :owner) do
      {_uid, gid} when is_integer(gid) and gid >= 0 ->
        with {:ok, %{type: :directory, uid: uid}} <- File.lstat(path),
             :ok <- change_owner(path, uid, gid) do
          :ok
        else
          {:ok, _info} -> {:error, :unsafe_staged_directory}
          {:error, reason} -> {:error, {:ownership_failed, reason}}
        end

      nil ->
        :ok

      _invalid ->
        {:error, :invalid_staging_owner}
    end
  end

  defp apply_owner(path, config) do
    case Map.get(config, :owner) do
      {uid, gid} when is_integer(uid) and uid >= 0 and is_integer(gid) and gid >= 0 ->
        change_owner(path, uid, gid)

      nil ->
        :ok

      _invalid ->
        {:error, :invalid_staging_owner}
    end
  end

  defp change_owner(path, uid, gid) do
    case :file.change_owner(String.to_charlist(path), uid, gid) do
      :ok -> :ok
      {:error, reason} -> {:error, {:ownership_failed, reason}}
    end
  end

  defp sync_file(path) do
    case File.open(path, [:read, :raw], &:file.sync/1) do
      {:ok, :ok} -> :ok
      {:ok, {:error, reason}} -> {:error, {:file_sync_failed, reason}}
      {:error, reason} -> {:error, {:file_sync_failed, reason}}
    end
  end

  defp sync_directory(path) do
    case File.open(path, [:read, :raw, :directory], &:file.sync/1) do
      {:ok, :ok} -> :ok
      {:ok, {:error, reason}} -> {:error, {:directory_sync_failed, reason}}
      {:error, reason} -> {:error, {:directory_sync_failed, reason}}
    end
  end

  defp file_url(path), do: URI.to_string(%URI{scheme: "file", path: path})
end
