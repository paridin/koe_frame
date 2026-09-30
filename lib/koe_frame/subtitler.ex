defmodule Defdo.KoeFrame.Subtitler do
  @moduledoc """
  KoeFrame's generic subtitle-service boundary.

  KoeFrame sends extracted SRT text to Subtitler and receives normalized cue
  IDs and millisecond ranges. Video and audio bytes never cross this boundary.
  """

  alias Defdo.KoeFrame.Subtitler.{Adapter, HTTPAdapter}

  @max_srt_bytes 1_000_000

  @type cue :: Adapter.cue()

  @spec normalize_srt(binary()) :: {:ok, [cue()]} | {:error, atom()}
  def normalize_srt(content) when is_binary(content) do
    cond do
      byte_size(content) > @max_srt_bytes ->
        {:error, :payload_too_large}

      not String.valid?(content) ->
        {:error, :malformed_srt}

      true ->
        adapter().normalize_srt(content)
    end
  end

  def normalize_srt(_content), do: {:error, :malformed_srt}

  defp adapter do
    Application.get_env(:koe_frame, :subtitler_adapter, HTTPAdapter)
  end
end
