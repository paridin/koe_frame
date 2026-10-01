defmodule Mix.Tasks.KoeFrame.TranscriptReviewTest do
  use ExUnit.Case, async: false

  import ExUnit.CaptureIO

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
    :transcript_review_tenant_id,
    :speaches_model,
    :speaches_base_url
  ]

  setup do
    root =
      Path.join(
        System.tmp_dir!(),
        "koe-frame-transcript-cli-#{System.unique_integer([:positive])}"
      )

    File.mkdir_p!(root)
    path = Path.join(root, "sample.mkv")
    File.write!(path, "synthetic media")
    previous = Enum.map(@config_keys, &{&1, Application.fetch_env(:koe_frame, &1)})

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
    Application.put_env(:koe_frame, :transcript_review_tenant_id, "tenant-transcript-test")
    Application.put_env(:koe_frame, :speaches_model, "test/model")
    Application.put_env(:koe_frame, :speaches_base_url, "http://speaches.test.invalid")

    on_exit(fn ->
      Enum.each(previous, fn
        {key, {:ok, value}} -> Application.put_env(:koe_frame, key, value)
        {key, :error} -> Application.delete_env(:koe_frame, key)
      end)

      File.rm_rf!(root)
    end)

    {:ok, path: path}
  end

  test "--list-streams prints normalized JSON without requiring tenant context", %{path: path} do
    output =
      capture_io(fn ->
        Mix.Tasks.KoeFrame.TranscriptReview.run(["--file", path, "--list-streams"])
      end)

    assert %{"duration_ms" => 60_123, "streams" => streams} = Jason.decode!(output)
    assert Enum.map(streams, & &1["index"]) == [1, 3]
  end

  test "preview prints one JSON alignment report", %{path: path} do
    args = [
      "--file",
      path,
      "--audio-stream",
      "1",
      "--subtitle-stream",
      "3",
      "--source-language",
      "ja",
      "--start-ms",
      "0",
      "--duration-ms",
      "10000"
    ]

    output = capture_io(fn -> Mix.Tasks.KoeFrame.TranscriptReview.run(args) end)

    assert %{"model" => "test/model", "words" => [%{"cue_ids" => ["cue-1"]}]} =
             Jason.decode!(output)
  end

  test "missing preview options and provider failures exit without a partial report", %{
    path: path
  } do
    assert_raise Mix.Error, fn ->
      Mix.Tasks.KoeFrame.TranscriptReview.run(["--file", path])
    end

    Process.put(:transcript_review_words, {:error, :speaches_unavailable})

    args = [
      "--file",
      path,
      "--audio-stream",
      "1",
      "--subtitle-stream",
      "3",
      "--source-language",
      "ja",
      "--start-ms",
      "0",
      "--duration-ms",
      "10000"
    ]

    output =
      capture_io(fn ->
        assert_raise Mix.Error, fn -> Mix.Tasks.KoeFrame.TranscriptReview.run(args) end
      end)

    assert output == ""
  end

  test "preview requires a configured tenant for Vault-backed Subtitler access", %{path: path} do
    Application.delete_env(:koe_frame, :transcript_review_tenant_id)

    args = [
      "--file",
      path,
      "--audio-stream",
      "1",
      "--subtitle-stream",
      "3",
      "--source-language",
      "ja",
      "--start-ms",
      "0",
      "--duration-ms",
      "10000"
    ]

    assert_raise Mix.Error, fn ->
      Mix.Tasks.KoeFrame.TranscriptReview.run(args)
    end

    refute_received {:transcript_review_fake, {:probe, _path}}
  end
end
