defmodule Defdo.KoeFrame.SubtitlerTest do
  use ExUnit.Case, async: true

  alias Defdo.KoeFrame.Subtitler

  test "rejects oversized subtitle documents before calling the service" do
    assert {:error, :payload_too_large} =
             Subtitler.normalize_srt(String.duplicate("x", 1_000_001))
  end

  test "rejects invalid UTF-8 before calling the service" do
    assert {:error, :malformed_srt} = Subtitler.normalize_srt(<<255, 254>>)
  end

  test "rejects non-binary inputs" do
    assert {:error, :malformed_srt} = Subtitler.normalize_srt(nil)
  end
end
