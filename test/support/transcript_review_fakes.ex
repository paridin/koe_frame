defmodule Defdo.KoeFrame.TranscriptReviewTest.FakeMediaAdapter do
  @behaviour Defdo.KoeFrame.MediaAnalysis.Adapter

  alias Defdo.KoeFrame.MediaAnalysis.{MediaInfo, MediaStream}

  @impl true
  def probe(path) do
    record({:probe, path})

    case Process.get(:transcript_review_info) do
      nil -> {:ok, default_info()}
      result -> result
    end
  end

  @impl true
  def extract_subtitle(_source_path, stream_index, output_path, format) do
    record({:subtitle, stream_index, output_path, format})

    File.write!(
      output_path,
      Process.get(:transcript_review_srt, "1\n00:00:01,000 --> 00:00:02,000\nHello\n")
    )

    {:ok, output_path}
  end

  @impl true
  def extract_audio_segment(
        _source_path,
        stream_index,
        start_ms,
        duration_ms,
        output_path,
        profile
      ) do
    record({:audio, stream_index, start_ms, duration_ms, output_path, profile})
    File.write!(output_path, "synthetic wav bytes")
    {:ok, output_path}
  end

  defp record(message) do
    case Process.get(:transcript_review_owner) do
      nil -> :ok
      owner -> send(owner, {:transcript_review_fake, message})
    end
  end

  defp default_info do
    %MediaInfo{
      format_name: "matroska,webm",
      duration: 60.123,
      size: 100,
      streams: [
        %MediaStream{index: 1, codec_type: "audio", codec_name: "aac"},
        %MediaStream{index: 3, codec_type: "subtitle", codec_name: "ass"}
      ]
    }
  end
end

defmodule Defdo.KoeFrame.TranscriptReviewTest.FakeASRAdapter do
  @behaviour Defdo.KoeFrame.TranscriptReview.Adapter

  @impl true
  def configuration do
    Process.get(:transcript_review_asr_config, {:ok, %{model: "test/model"}})
  end

  @impl true
  def transcribe(audio_path, language, duration_ms) do
    case Process.get(:transcript_review_owner) do
      nil ->
        :ok

      owner ->
        send(owner, {:transcript_review_fake, {:transcribe, audio_path, language, duration_ms}})
    end

    Process.get(:transcript_review_words, {:ok, [%{text: "hello", start_ms: 0, end_ms: 500}]})
  end
end

defmodule Defdo.KoeFrame.TranscriptReviewTest.FakeSubtitlerAdapter do
  @behaviour Defdo.KoeFrame.Subtitler.Adapter

  @impl true
  def normalize_srt(content) do
    case Process.get(:transcript_review_owner) do
      nil -> :ok
      owner -> send(owner, {:transcript_review_fake, {:normalize_srt, content}})
    end

    Process.get(
      :transcript_review_cues,
      {:ok, [%{id: "cue-1", start_ms: 0, end_ms: 2_000, text: "Hello"}]}
    )
  end
end
