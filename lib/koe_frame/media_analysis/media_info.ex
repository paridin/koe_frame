defmodule Defdo.KoeFrame.MediaAnalysis.MediaInfo do
  @moduledoc "Normalized format and stream metadata for a local media file."

  alias Defdo.KoeFrame.MediaAnalysis.MediaStream

  @type t :: %__MODULE__{
          format_name: String.t() | nil,
          duration: float() | nil,
          size: non_neg_integer() | nil,
          streams: [MediaStream.t()]
        }

  defstruct [:format_name, :duration, :size, streams: []]

  @doc false
  def from_ffprobe(format, streams) when is_map(format) and is_list(streams) do
    %__MODULE__{
      format_name: Map.get(format, "format_name"),
      duration: decimal(Map.get(format, "duration")),
      size: integer(Map.get(format, "size")),
      streams: Enum.map(streams, &MediaStream.from_ffprobe/1)
    }
  end

  def from_ffprobe(_format, _streams), do: %__MODULE__{}

  defp decimal(value) when is_number(value), do: value * 1.0

  defp decimal(value) when is_binary(value) do
    case Float.parse(value) do
      {number, ""} -> number
      _ -> nil
    end
  end

  defp decimal(_value), do: nil

  defp integer(value) when is_integer(value) and value >= 0, do: value

  defp integer(value) when is_binary(value) do
    case Integer.parse(value) do
      {number, ""} when number >= 0 -> number
      _ -> nil
    end
  end

  defp integer(_value), do: nil
end
