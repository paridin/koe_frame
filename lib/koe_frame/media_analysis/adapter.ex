defmodule Defdo.KoeFrame.MediaAnalysis.Adapter do
  @moduledoc """
  Boundary between KoeFrame's media analysis workflow and a media toolchain.

  Implementations own FFmpeg/FFprobe process details. Callers use KoeFrame data
  types so another runner can replace the CLI adapter without changing the
  localization workflow.
  """

  alias Defdo.KoeFrame.MediaAnalysis.MediaInfo

  @callback probe(source_path :: Path.t()) ::
              {:ok, MediaInfo.t()} | {:error, term()}

  @callback extract_subtitle(
              source_path :: Path.t(),
              stream_index :: non_neg_integer(),
              output_path :: Path.t(),
              opts :: keyword()
            ) :: {:ok, Path.t()} | {:error, term()}

  @callback extract_audio_segment(
              source_path :: Path.t(),
              stream_index :: non_neg_integer(),
              start_seconds :: number(),
              duration_seconds :: pos_integer() | float(),
              output_path :: Path.t(),
              opts :: keyword()
            ) :: {:ok, Path.t()} | {:error, term()}
end
