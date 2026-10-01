defmodule Defdo.KoeFrame.MediaAnalysis.MediaStream do
  @moduledoc "A selected set of media stream facts normalized for KoeFrame."

  defstruct [
    :index,
    :media_type,
    :codec_name,
    :language,
    :title,
    :width,
    :height,
    :sample_rate,
    :channels,
    default?: false,
    forced?: false,
    attached_picture?: false
  ]

  @type t :: %__MODULE__{
          index: non_neg_integer(),
          media_type: String.t(),
          codec_name: String.t() | nil,
          language: String.t() | nil,
          title: String.t() | nil,
          width: non_neg_integer() | nil,
          height: non_neg_integer() | nil,
          sample_rate: non_neg_integer() | nil,
          channels: non_neg_integer() | nil,
          default?: boolean(),
          forced?: boolean(),
          attached_picture?: boolean()
        }

  @spec from_ffprobe(map()) :: {:ok, t()} | {:error, :invalid_probe_result}
  def from_ffprobe(stream) when is_map(stream) do
    index = integer_value(stream["index"])
    media_type = stream["codec_type"]
    tags = stream["tags"] || %{}
    disposition = stream["disposition"] || %{}

    if is_integer(index) and index >= 0 and is_binary(media_type) do
      {:ok,
       %__MODULE__{
         index: index,
         media_type: media_type,
         codec_name: stream["codec_name"],
         language: tags["language"],
         title: tags["title"],
         width: integer_value(stream["width"]),
         height: integer_value(stream["height"]),
         sample_rate: integer_value(stream["sample_rate"]),
         channels: integer_value(stream["channels"]),
         default?: enabled?(disposition["default"]),
         forced?: enabled?(disposition["forced"]),
         attached_picture?: enabled?(disposition["attached_pic"])
       }}
    else
      {:error, :invalid_probe_result}
    end
  end

  def from_ffprobe(_stream), do: {:error, :invalid_probe_result}

  defp integer_value(value) when is_integer(value), do: value

  defp integer_value(value) when is_binary(value) do
    case Integer.parse(value) do
      {number, _rest} -> number
      :error -> nil
    end
  end

  defp integer_value(_value), do: nil

  defp enabled?(true), do: true
  defp enabled?(1), do: true
  defp enabled?("1"), do: true
  defp enabled?(_value), do: false
end
