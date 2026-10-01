defmodule Defdo.KoeFrame.MediaIntake.Digest do
  @moduledoc false

  @read_bytes 1024 * 1024

  @spec sha256(Path.t()) :: {:ok, String.t()} | {:error, term()}
  def sha256(path) when is_binary(path) do
    case File.open(path, [:read, :binary], fn io ->
           hash_stream(io, :crypto.hash_init(:sha256))
         end) do
      {:ok, {:ok, digest}} -> {:ok, Base.encode16(digest, case: :lower)}
      {:ok, {:error, reason}} -> {:error, reason}
      {:error, reason} -> {:error, reason}
    end
  end

  defp hash_stream(io, context) do
    case IO.binread(io, @read_bytes) do
      :eof -> {:ok, :crypto.hash_final(context)}
      {:error, reason} -> {:error, reason}
      bytes when is_binary(bytes) -> hash_stream(io, :crypto.hash_update(context, bytes))
    end
  end
end
