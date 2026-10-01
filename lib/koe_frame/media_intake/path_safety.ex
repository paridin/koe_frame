defmodule Defdo.KoeFrame.MediaIntake.PathSafety do
  @moduledoc """
  Checks that a configured storage root cannot be renamed by its group or by
  other local users through a writable ancestor directory.
  """

  import Bitwise, only: [band: 2]

  @spec validate_root_parent(Path.t()) :: :ok | {:error, term()}
  def validate_root_parent(root) when is_binary(root) do
    if Path.type(root) == :absolute do
      validate_parent_chain(root |> Path.expand() |> Path.dirname(), 0)
    else
      {:error, :filesystem_root_must_be_absolute}
    end
  end

  def validate_root_parent(_root), do: {:error, :invalid_filesystem_root}

  defp validate_parent_chain(_path, attempts) when attempts > 40,
    do: {:error, :unsafe_filesystem_root_parent}

  defp validate_parent_chain(path, attempts) do
    path = Path.expand(path)

    result =
      path
      |> directory_chain()
      |> Enum.reverse()
      |> Enum.reduce_while(:ok, fn directory, :ok ->
        case File.lstat(directory) do
          {:ok, %{type: :directory, mode: mode}} ->
            if band(mode, 0o022) == 0,
              do: {:cont, :ok},
              else: {:halt, {:error, :unsafe_filesystem_root_parent}}

          {:ok, %{type: :symlink}} ->
            case File.read_link(directory) do
              {:ok, target} ->
                target =
                  if Path.type(target) == :absolute,
                    do: target,
                    else: Path.expand(target, Path.dirname(directory))

                suffix = Path.relative_to(path, directory)
                resolved = if suffix == ".", do: target, else: Path.join(target, suffix)
                {:halt, {:restart, resolved}}

              {:error, reason} ->
                {:halt, {:error, {:filesystem_root_parent_unavailable, reason}}}
            end

          {:ok, _info} ->
            {:halt, {:error, :unsafe_filesystem_root_parent}}

          {:error, reason} ->
            {:halt, {:error, {:filesystem_root_parent_unavailable, reason}}}
        end
      end)

    case result do
      {:restart, resolved} -> validate_parent_chain(resolved, attempts + 1)
      other -> other
    end
  end

  defp directory_chain(path) do
    parent = Path.dirname(path)
    if parent == path, do: [path], else: [path | directory_chain(parent)]
  end
end
