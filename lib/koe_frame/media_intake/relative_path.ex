defmodule Defdo.KoeFrame.MediaIntake.RelativePath do
  @moduledoc """
  Validates a file path relative to one intake root.

  Client paths are labels within a server-created intake directory. They are
  never interpreted as final library paths or joined to a path outside staging.
  """

  @max_path_bytes 4096
  @max_segment_bytes 255

  @spec validate(term()) :: {:ok, String.t()} | {:error, :invalid_relative_path}
  def validate(path) when is_binary(path) do
    segments = String.split(path, "/", trim: false)

    valid? =
      path != "" and byte_size(path) <= @max_path_bytes and
        Path.type(path) == :relative and not String.contains?(path, <<0>>) and
        not String.contains?(path, "\\") and
        Enum.all?(segments, fn segment ->
          segment not in ["", ".", ".."] and byte_size(segment) <= @max_segment_bytes
        end)

    if valid?, do: {:ok, path}, else: {:error, :invalid_relative_path}
  end

  def validate(_path), do: {:error, :invalid_relative_path}
end
