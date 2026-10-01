defmodule Defdo.KoeFrame.TranscriptReview.Alignment do
  @moduledoc false

  @doc false
  def report(words, cues, clip_start_ms, duration_ms) do
    clip_end_ms = clip_start_ms + duration_ms

    visible_cues =
      Enum.filter(cues, &overlaps?(&1.start_ms, &1.end_ms, clip_start_ms, clip_end_ms))

    visible_words =
      words
      |> Enum.with_index()
      |> Enum.sort_by(fn {word, index} -> {word.start_ms, index} end)
      |> Enum.map(fn {word, _index} ->
        start_ms = clip_start_ms + word.start_ms
        end_ms = clip_start_ms + word.end_ms

        %{
          text: word.text,
          start_ms: start_ms,
          end_ms: end_ms,
          cue_ids:
            visible_cues
            |> Enum.filter(&word_overlaps?(&1, start_ms, end_ms))
            |> Enum.map(& &1.id)
        }
      end)

    %{
      clip_start_ms: clip_start_ms,
      clip_end_ms: clip_end_ms,
      words: visible_words,
      cues:
        Enum.map(visible_cues, fn cue ->
          %{id: cue.id, start_ms: cue.start_ms, end_ms: cue.end_ms, text: cue.text}
        end)
    }
  end

  defp overlaps?(start_a, end_a, start_b, end_b), do: start_a < end_b and end_a > start_b

  defp word_overlaps?(cue, start_ms, end_ms) when start_ms == end_ms do
    cue.start_ms <= start_ms and start_ms < cue.end_ms
  end

  defp word_overlaps?(cue, start_ms, end_ms),
    do: overlaps?(cue.start_ms, cue.end_ms, start_ms, end_ms)
end
