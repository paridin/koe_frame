defmodule Defdo.KoeFrame.Subtitler.Adapter do
  @moduledoc """
  Boundary for normalizing subtitle documents through the generic Subtitler
  service.
  """

  @type cue :: %{
          id: String.t(),
          start_ms: non_neg_integer(),
          end_ms: pos_integer(),
          text: String.t()
        }

  @callback normalize_srt(binary()) :: {:ok, [cue()]} | {:error, atom()}
end
