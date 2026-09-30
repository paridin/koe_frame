defmodule Defdo.KoeFrame.MediaAnalysis.Adapter do
  @moduledoc "Application boundary for probing and extracting local media."

  alias Defdo.KoeFrame.MediaAnalysis.MediaInfo

  @callback probe(source_path :: binary()) :: {:ok, MediaInfo.t()} | {:error, atom()}

  @callback extract_subtitle(
              source_path :: binary(),
              stream_index :: non_neg_integer(),
              output_path :: binary(),
              output_format :: binary() | nil
            ) :: {:ok, term()} | {:error, atom() | {atom(), non_neg_integer()}}

  @callback extract_audio_segment(
              source_path :: binary(),
              stream_index :: non_neg_integer(),
              start_ms :: non_neg_integer(),
              duration_ms :: pos_integer(),
              output_path :: binary(),
              profile :: %{sample_rate: pos_integer(), channels: pos_integer()}
            ) :: {:ok, term()} | {:error, atom() | {atom(), non_neg_integer()}}
end
