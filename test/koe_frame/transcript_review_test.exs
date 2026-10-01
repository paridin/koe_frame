defmodule Defdo.KoeFrame.TranscriptReviewTest do
  use ExUnit.Case, async: false

  alias Defdo.KoeFrame.MediaAnalysis.{MediaInfo, MediaStream}
  alias Defdo.KoeFrame.TranscriptReview
  alias Defdo.Tenant.Context

  alias Defdo.KoeFrame.TranscriptReviewTest.{
    FakeASRAdapter,
    FakeMediaAdapter,
    FakeSubtitlerAdapter
  }

  @config_keys [
    :runtime_env,
    :media_analysis_adapter,
    :transcript_review_adapter,
    :subtitler_adapter,
    :speaches_base_url,
    :speaches_model,
    :speaches_timeout_ms
  ]

  setup do
    root =
      Path.join(
        System.tmp_dir!(),
        "koe-frame-transcript-test-#{System.unique_integer([:positive])}"
      )

    File.mkdir_p!(root)
    source_path = Path.join(root, "sample.mkv")
    File.write!(source_path, "synthetic media")

    previous = Enum.map(@config_keys, &{&1, Application.fetch_env(:koe_frame, &1)})
    Context.clear()
    Process.put(:transcript_review_owner, self())
    Process.delete(:transcript_review_info)
    Process.delete(:transcript_review_srt)
    Process.delete(:transcript_review_cues)
    Process.delete(:transcript_review_words)
    Process.delete(:transcript_review_asr_config)

    Application.put_env(:koe_frame, :runtime_env, :test)
    Application.put_env(:koe_frame, :media_analysis_adapter, FakeMediaAdapter)
    Application.put_env(:koe_frame, :transcript_review_adapter, FakeASRAdapter)
    Application.put_env(:koe_frame, :subtitler_adapter, FakeSubtitlerAdapter)
    Application.put_env(:koe_frame, :speaches_base_url, "http://speaches.test.invalid")
    Application.put_env(:koe_frame, :speaches_model, "test/model")
    Application.put_env(:koe_frame, :speaches_timeout_ms, 1_000)

    on_exit(fn ->
      Enum.each(previous, fn
        {key, {:ok, value}} -> Application.put_env(:koe_frame, key, value)
        {key, :error} -> Application.delete_env(:koe_frame, key)
      end)

      Context.clear()
      File.rm_rf!(root)
    end)

    {:ok, source_path: source_path}
  end

  test "stream inventory preserves global indexes and floors media duration", %{source_path: path} do
    assert {:ok, %{duration_ms: 60_123, streams: streams}} =
             TranscriptReview.stream_inventory(path)

    assert Enum.map(streams, & &1.index) == [1, 3]
  end

  test "previews word and cue alignment on the source timeline and removes temporary files", %{
    source_path: path
  } do
    Process.put(:transcript_review_srt, "converted ASS subtitle")

    Process.put(:transcript_review_cues, {
      :ok,
      [
        %{id: "cue-before", start_ms: 5_910, end_ms: 9_480, text: "outside clip"},
        %{id: "cue-a", start_ms: 13_190, end_ms: 18_490, text: "<font>spoken line</font>"},
        %{id: "cue-b", start_ms: 17_500, end_ms: 18_200, text: "overlapping cue"},
        %{id: "cue-c", start_ms: 39_800, end_ms: 42_000, text: "crosses clip end"},
        %{id: "cue-touch", start_ms: 40_000, end_ms: 43_000, text: "starts at clip end"}
      ]
    })

    Process.put(:transcript_review_words, {
      :ok,
      [
        %{text: "first", start_ms: 3_000, end_ms: 3_500},
        %{text: "point", start_ms: 6_000, end_ms: 6_000},
        %{text: "unmatched", start_ms: 20_000, end_ms: 21_000},
        %{text: "last", start_ms: 29_800, end_ms: 30_000}
      ]
    })

    result =
      Context.with_context("tenant-transcript-review", fn ->
        TranscriptReview.preview(request(path, start_ms: 10_000, duration_ms: 30_000))
      end)

    assert {:ok, report} = result
    assert report.model == "test/model"
    assert report.source_language == "ja"
    assert report.audio_stream_index == 1
    assert report.subtitle_stream_index == 3
    assert report.clip_start_ms == 10_000
    assert report.clip_end_ms == 40_000
    assert Enum.map(report.cues, & &1.id) == ["cue-a", "cue-b", "cue-c"]
    assert Enum.map(report.words, & &1.cue_ids) == [["cue-a"], ["cue-a"], [], ["cue-c"]]
    assert hd(report.words).start_ms == 13_000
    assert hd(report.words).end_ms == 13_500
    assert Enum.at(report.words, 1).start_ms == 16_000

    assert_received {:transcript_review_fake, {:subtitle, 3, subtitle_path, "srt"}}
    assert_received {:transcript_review_fake, {:normalize_srt, "converted ASS subtitle"}}
    assert_received {:transcript_review_fake, {:audio, 1, 10_000, 30_000, audio_path, _profile}}
    assert_received {:transcript_review_fake, {:transcribe, ^audio_path, "ja", 30_000}}
    refute File.exists?(subtitle_path)
    refute File.exists?(audio_path)
    refute File.exists?(Path.dirname(subtitle_path))
  end

  test "requires tenant context before probing or making service calls", %{source_path: path} do
    Context.clear()

    assert {:error, :missing_tenant_context} = TranscriptReview.preview(request(path))
    refute_received {:transcript_review_fake, _message}
  end

  test "rejects bitmap and unknown subtitle codecs before extraction", %{source_path: path} do
    Process.put(:transcript_review_info, {:ok, info("hdmv_pgs_subtitle")})

    assert {:error, :unsupported_subtitle_codec} =
             Context.with_context("tenant-transcript-review", fn ->
               TranscriptReview.preview(request(path))
             end)

    assert_received {:transcript_review_fake, {:probe, ^path}}
    refute_received {:transcript_review_fake, {:subtitle, _, _, _}}
    refute_received {:transcript_review_fake, {:transcribe, _, _, _}}
  end

  test "rejects an out-of-media clip before extracting either stream", %{source_path: path} do
    assert {:error, :clip_outside_media} =
             Context.with_context("tenant-transcript-review", fn ->
               TranscriptReview.preview(request(path, start_ms: 60_000, duration_ms: 1_000))
             end)

    assert_received {:transcript_review_fake, {:probe, ^path}}
    refute_received {:transcript_review_fake, {:subtitle, _, _, _}}
    refute_received {:transcript_review_fake, {:audio, _, _, _, _, _}}
  end

  test "does not transcribe audio when Subtitler rejects the extracted SRT and cleans up", %{
    source_path: path
  } do
    Process.put(:transcript_review_cues, {:error, :malformed_srt})

    assert {:error, :malformed_srt} =
             Context.with_context("tenant-transcript-review", fn ->
               TranscriptReview.preview(request(path))
             end)

    assert_received {:transcript_review_fake, {:subtitle, _index, subtitle_path, "srt"}}
    refute_received {:transcript_review_fake, {:audio, _, _, _, _, _}}
    refute File.exists?(subtitle_path)
    refute File.exists?(Path.dirname(subtitle_path))
  end

  test "rejects duplicate Subtitler cue IDs and removes extracted files", %{source_path: path} do
    cue = %{id: "duplicate", start_ms: 0, end_ms: 1_000, text: "cue"}
    Process.put(:transcript_review_cues, {:ok, [cue, cue]})

    assert {:error, :invalid_subtitler_response} =
             Context.with_context("tenant-transcript-review", fn ->
               TranscriptReview.preview(request(path))
             end)

    assert_received {:transcript_review_fake, {:subtitle, _index, subtitle_path, "srt"}}
    refute_received {:transcript_review_fake, {:audio, _, _, _, _, _}}
    refute File.exists?(Path.dirname(subtitle_path))
  end

  test "rejects malformed preview arguments before probing", %{source_path: path} do
    assert {:error, :invalid_source_language} =
             TranscriptReview.preview(request(path, source_language: "jpn"))

    assert {:error, :clip_too_long} =
             TranscriptReview.preview(request(path, duration_ms: 60_001))

    refute_received {:transcript_review_fake, _message}
  end

  defp request(path, overrides \\ []) do
    Map.merge(
      %{
        path: path,
        audio_stream: 1,
        subtitle_stream: 3,
        source_language: "ja",
        start_ms: 0,
        duration_ms: 10_000
      },
      Map.new(overrides)
    )
  end

  defp info(subtitle_codec) do
    %MediaInfo{
      duration: 60.123,
      streams: [
        %MediaStream{index: 1, codec_type: "audio", codec_name: "aac"},
        %MediaStream{index: 3, codec_type: "subtitle", codec_name: subtitle_codec}
      ]
    }
  end
end
