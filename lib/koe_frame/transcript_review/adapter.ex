defmodule Defdo.KoeFrame.TranscriptReview.Adapter do
  @moduledoc """
  Boundary for word-level speech transcription of one extracted audio clip.
  """

  @type word :: %{
          text: String.t(),
          start_ms: non_neg_integer(),
          end_ms: non_neg_integer()
        }

  @callback configuration() :: {:ok, %{model: String.t()}} | {:error, atom()}
  @callback transcribe(Path.t(), String.t(), pos_integer()) ::
              {:ok, [word()]} | {:error, atom()}
end
