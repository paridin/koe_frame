defmodule Defdo.KoeFrame.MediaAnalysisTest do
  use ExUnit.Case, async: false

  alias Defdo.KoeFrame.MediaAnalysis
  alias Defdo.KoeFrame.MediaAnalysis.MediaInfo

  setup do
    root =
      Path.join(
        System.tmp_dir!(),
        "koe-frame-media-analysis-#{System.unique_integer([:positive])}"
      )

    source_path = Path.join(root, "source.media")
    output_dir = Path.join(root, "output")

    File.mkdir_p!(output_dir)
    File.write!(source_path, "fixture bytes")

    previous_adapter = Application.fetch_env(:koe_frame, :media_analysis_adapter)

    Application.put_env(
      :koe_frame,
      :media_analysis_adapter,
      Defdo.KoeFrame.MediaAnalysisTest.FakeAdapter
    )

    Process.put(:media_analysis_calls, [])
    Process.delete(:media_analysis_probe_result)
    Process.delete(:media_analysis_subtitle_result)
    Process.delete(:media_analysis_audio_result)

    on_exit(fn ->
      restore_env(:media_analysis_adapter, previous_adapter)
      File.rm_rf!(root)
    end)

    {:ok, source_path: source_path, output_dir: output_dir}
  end

  test "probe routes through the configured adapter and returns its normalized result", %{
    source_path: source_path
  } do
    info = %MediaInfo{format_name: "matroska", duration: 4.5, size: 100, streams: []}
    Process.put(:media_analysis_probe_result, {:ok, info})

    assert {:ok, ^info} = MediaAnalysis.probe(source_path)
    assert [{:probe, ^source_path}] = calls()
  end

  test "audio extraction supplies the default profile and verifies a non-empty output", context do
    output_path = output_path(context, "audio.wav")

    assert {:ok, ^output_path} =
             MediaAnalysis.extract_audio_segment(
               context.source_path,
               5,
               1_250,
               2_500,
               output_path,
               nil
             )

    assert [
             {:extract_audio_segment,
              [_, 5, 1_250, 2_500, ^output_path, %{sample_rate: 16_000, channels: 1}]}
           ] =
             calls()

    assert File.read!(output_path) == "extracted media"
  end

  test "audio extraction accepts a validated custom profile", context do
    output_path = output_path(context, "custom.wav")

    assert {:ok, ^output_path} =
             MediaAnalysis.extract_audio_segment(
               context.source_path,
               2,
               0,
               60_000,
               output_path,
               sample_rate: 22_050,
               channels: 2
             )

    assert [
             {:extract_audio_segment,
              [_, 2, 0, 60_000, ^output_path, %{sample_rate: 22_050, channels: 2}]}
           ] =
             calls()
  end

  test "subtitle extraction routes the selected stream and requested output format", context do
    output_path = output_path(context, "selected.srt")

    assert {:ok, ^output_path} =
             MediaAnalysis.extract_subtitle(context.source_path, 7, output_path, "srt")

    assert [{:extract_subtitle, [_, 7, ^output_path, "srt"]}] = calls()
  end

  test "invalid sources and stream indexes are rejected before adapter invocation", context do
    missing = Path.join(context.output_dir, "missing.media")
    relative_source = "relative.media"
    directory_source = context.output_dir

    assert {:error, :source_file_not_found} = MediaAnalysis.probe(missing)
    assert {:error, :source_path_must_be_absolute} = MediaAnalysis.probe(relative_source)

    assert {:error, :source_not_regular_file} =
             MediaAnalysis.extract_subtitle(
               directory_source,
               0,
               output_path(context, "dir.srt"),
               nil
             )

    assert {:error, :invalid_stream_index} =
             MediaAnalysis.extract_subtitle(
               context.source_path,
               -1,
               output_path(context, "bad.srt"),
               nil
             )

    assert {:error, :invalid_stream_index} =
             MediaAnalysis.extract_subtitle(
               context.source_path,
               "0",
               output_path(context, "bad-type.srt"),
               nil
             )

    assert calls() == []
  end

  test "invalid time ranges and segments over one minute are rejected before adapter invocation",
       context do
    output_path = output_path(context, "audio.wav")

    for {start_ms, duration_ms, expected} <- [
          {-1, 1_000, :invalid_time_range},
          {0, 0, :invalid_time_range},
          {0, 1.5, :invalid_time_range},
          {0, 60_001, :segment_too_long}
        ] do
      assert {:error, ^expected} =
               MediaAnalysis.extract_audio_segment(
                 context.source_path,
                 0,
                 start_ms,
                 duration_ms,
                 output_path,
                 nil
               )
    end

    assert calls() == []
  end

  test "invalid audio profiles are rejected before adapter invocation", context do
    for profile <- [
          %{sample_rate: 0},
          %{channels: -1},
          %{sample_rate: "16000"},
          %{sample_rate: 16_000, channels: 1, codec: "mp3"},
          [sample_rate: 16_000, channels: 0],
          "mono"
        ] do
      assert {:error, :invalid_audio_profile} =
               MediaAnalysis.extract_audio_segment(
                 context.source_path,
                 0,
                 0,
                 1_000,
                 output_path(context, "audio.wav"),
                 profile
               )
    end

    assert calls() == []
  end

  test "invalid and existing output paths are rejected before adapter invocation", context do
    assert {:error, :output_path_must_be_absolute} =
             MediaAnalysis.extract_subtitle(context.source_path, 0, "relative.srt", nil)

    missing_directory =
      Path.join(System.tmp_dir!(), "missing-koe-frame-#{System.unique_integer([:positive])}")

    assert {:error, :output_directory_not_found} =
             MediaAnalysis.extract_subtitle(
               context.source_path,
               0,
               Path.join(missing_directory, "x.srt"),
               nil
             )

    existing_path = output_path(context, "existing.srt")
    File.write!(existing_path, "already here")

    assert {:error, :output_already_exists} =
             MediaAnalysis.extract_subtitle(context.source_path, 0, existing_path, nil)

    assert {:error, :invalid_output_format} =
             MediaAnalysis.extract_subtitle(
               context.source_path,
               0,
               output_path(context, "format.srt"),
               "bad format"
             )

    assert calls() == []
  end

  test "adapter failures are reduced to stable errors without command output", context do
    output_path = output_path(context, "failed.srt")
    Process.put(:media_analysis_subtitle_result, {:error, {:ffmpeg_failed, 23}})

    assert {:error, {:ffmpeg_failed, 23}} =
             MediaAnalysis.extract_subtitle(context.source_path, 1, output_path, nil)
  end

  test "successful adapter response is rejected when it did not create output", context do
    output_path = output_path(context, "missing-output.srt")
    Process.put(:media_analysis_subtitle_result, {:ok, :without_file})

    assert {:error, :output_not_created} =
             MediaAnalysis.extract_subtitle(context.source_path, 1, output_path, nil)
  end

  test "empty outputs and adapter-side overwrite races keep their stable errors", context do
    empty_path = output_path(context, "empty.srt")
    Process.put(:media_analysis_subtitle_result, :empty_output)

    assert {:error, :output_empty} =
             MediaAnalysis.extract_subtitle(context.source_path, 1, empty_path, nil)

    race_path = output_path(context, "race.srt")
    Process.put(:media_analysis_subtitle_result, {:error, :output_already_exists})

    assert {:error, :output_already_exists} =
             MediaAnalysis.extract_subtitle(context.source_path, 1, race_path, nil)
  end

  defp output_path(context, filename), do: Path.join(context.output_dir, filename)

  defp calls, do: Process.get(:media_analysis_calls, []) |> Enum.reverse()

  defp restore_env(key, {:ok, value}), do: Application.put_env(:koe_frame, key, value)
  defp restore_env(key, :error), do: Application.delete_env(:koe_frame, key)
end

defmodule Defdo.KoeFrame.MediaAnalysisTest.FakeAdapter do
  @behaviour Defdo.KoeFrame.MediaAnalysis.Adapter

  def probe(source_path) do
    record({:probe, source_path})
    Process.get(:media_analysis_probe_result, {:ok, %Defdo.KoeFrame.MediaAnalysis.MediaInfo{}})
  end

  def extract_subtitle(source_path, stream_index, output_path, output_format) do
    record({:extract_subtitle, [source_path, stream_index, output_path, output_format]})
    extraction_result(:media_analysis_subtitle_result, output_path)
  end

  def extract_audio_segment(
        source_path,
        stream_index,
        start_ms,
        duration_ms,
        output_path,
        profile
      ) do
    record(
      {:extract_audio_segment,
       [source_path, stream_index, start_ms, duration_ms, output_path, profile]}
    )

    extraction_result(:media_analysis_audio_result, output_path)
  end

  defp extraction_result(key, output_path) do
    case Process.get(key, :write_output) do
      :write_output ->
        File.write!(output_path, "extracted media")
        {:ok, :extracted}

      :empty_output ->
        File.write!(output_path, "")
        {:ok, :extracted}

      result ->
        result
    end
  end

  defp record(call),
    do: Process.put(:media_analysis_calls, [call | Process.get(:media_analysis_calls, [])])
end
