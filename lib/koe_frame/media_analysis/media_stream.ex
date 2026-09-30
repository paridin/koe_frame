defmodule Defdo.KoeFrame.MediaAnalysis.MediaStream do
  @moduledoc "Normalized metadata for one FFprobe stream."

  @type t :: %__MODULE__{
          index: non_neg_integer() | nil,
          codec_type: String.t() | nil,
          codec_name: String.t() | nil,
          language: String.t() | nil,
          title: String.t() | nil,
          default: boolean() | nil,
          forced: boolean() | nil,
          width: pos_integer() | nil,
          height: pos_integer() | nil,
          sample_rate: pos_integer() | nil,
          channels: pos_integer() | nil,
          attached_picture: boolean() | nil
        }

  defstruct [
    :index,
    :codec_type,
    :codec_name,
    :language,
    :title,
    :default,
    :forced,
    :width,
    :height,
    :sample_rate,
    :channels,
    :attached_picture
  ]

  @doc false
  def from_ffprobe(stream) when is_map(stream) do
    tags = value(stream, "tags") || %{}
    disposition = value(stream, "disposition") || %{}

    %__MODULE__{
      index: integer(value(stream, "index")),
      codec_type: value(stream, "codec_type"),
      codec_name: value(stream, "codec_name"),
      language: value(tags, "language"),
      title: value(tags, "title"),
      default: boolean(value(disposition, "default")),
      forced: boolean(value(disposition, "forced")),
      width: integer(value(stream, "width")),
      height: integer(value(stream, "height")),
      sample_rate: integer(value(stream, "sample_rate")),
      channels: integer(value(stream, "channels")),
      attached_picture: boolean(value(disposition, "attached_pic"))
    }
  end

  def from_ffprobe(_stream), do: %__MODULE__{}

  defp value(map, key) when is_map(map), do: Map.get(map, key)
  defp value(_map, _key), do: nil

  defp integer(value) when is_integer(value) and value >= 0, do: value

  defp integer(value) when is_binary(value) do
    case Integer.parse(value) do
      {number, ""} when number >= 0 -> number
      _ -> nil
    end
  end

  defp integer(_value), do: nil

  defp boolean(value) when value in [0, "0", false], do: false
  defp boolean(value) when value in [1, "1", true], do: true
  defp boolean(_value), do: nil
end
