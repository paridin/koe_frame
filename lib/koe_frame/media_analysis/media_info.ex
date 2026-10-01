defmodule Defdo.KoeFrame.MediaAnalysis.MediaInfo do
  @moduledoc "Normalized container information owned by KoeFrame."

  alias Defdo.KoeFrame.MediaAnalysis.MediaStream

  @enforce_keys [:streams]
  defstruct [:format_name, :duration_seconds, :size_bytes, streams: []]

  @type t :: %__MODULE__{
          format_name: String.t() | nil,
          duration_seconds: float() | nil,
          size_bytes: non_neg_integer() | nil,
          streams: [MediaStream.t()]
        }

  @spec from_ffprobe(map(), [map()]) :: {:ok, t()} | {:error, :invalid_probe_result}
  def from_ffprobe(format, streams) when is_map(format) and is_list(streams) do
    with {:ok, normalized_streams} <- normalize_streams(streams) do
      {:ok,
       %__MODULE__{
         format_name: format["format_name"],
         duration_seconds: parse_float(format["duration"]),
         size_bytes: parse_integer(format["size"]),
         streams: normalized_streams
       }}
    end
  end

  def from_ffprobe(_format, _streams), do: {:error, :invalid_probe_result}

  defp normalize_streams(streams) do
    Enum.reduce_while(streams, {:ok, []}, fn stream, {:ok, acc} ->
      case MediaStream.from_ffprobe(stream) do
        {:ok, normalized} -> {:cont, {:ok, [normalized | acc]}}
        {:error, :invalid_probe_result} = error -> {:halt, error}
      end
    end)
    |> case do
      {:ok, normalized} -> {:ok, Enum.reverse(normalized)}
      error -> error
    end
  end

  defp parse_float(value) when is_float(value), do: value * 1.0
  defp parse_float(value) when is_integer(value), do: value * 1.0

  defp parse_float(value) when is_binary(value) do
    case Float.parse(value) do
      {number, _rest} -> number
      :error -> nil
    end
  end

  defp parse_float(_value), do: nil

  defp parse_integer(value) when is_integer(value) and value >= 0, do: value

  defp parse_integer(value) when is_binary(value) do
    case Integer.parse(value) do
      {number, _rest} when number >= 0 -> number
      _other -> nil
    end
  end

  defp parse_integer(_value), do: nil
end
