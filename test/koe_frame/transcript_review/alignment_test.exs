defmodule Defdo.KoeFrame.TranscriptReview.AlignmentTest do
  use ExUnit.Case, async: true

  alias Defdo.KoeFrame.TranscriptReview.Alignment

  test "matches half-open intervals and treats zero-duration words as points" do
    words = [
      %{text: "inside", start_ms: 10, end_ms: 20},
      %{text: "touches right", start_ms: 20, end_ms: 20},
      %{text: "point inside", start_ms: 19, end_ms: 19}
    ]

    cues = [
      %{id: "cue-a", start_ms: 110, end_ms: 120, text: "A"},
      %{id: "cue-b", start_ms: 120, end_ms: 130, text: "B"}
    ]

    report = Alignment.report(words, cues, 100, 50)

    assert Enum.map(report.words, & &1.cue_ids) == [["cue-a"], ["cue-a"], ["cue-b"]]
  end

  test "keeps cue order and includes only cues that enter the half-open clip range" do
    words = [%{text: "word", start_ms: 0, end_ms: 1}]

    cues = [
      %{id: "before", start_ms: 0, end_ms: 9, text: "before"},
      %{id: "touch-start", start_ms: 9, end_ms: 10, text: "touch"},
      %{id: "inside", start_ms: 10, end_ms: 11, text: "inside"},
      %{id: "touch-end", start_ms: 20, end_ms: 21, text: "touch"},
      %{id: "after", start_ms: 21, end_ms: 22, text: "after"}
    ]

    report = Alignment.report(words, cues, 10, 10)

    assert Enum.map(report.cues, & &1.id) == ["inside"]
  end
end
