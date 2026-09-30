defmodule Defdo.KoeFrame.MediaAnalysisTest do
  use ExUnit.Case, async: false

  alias Defdo.KoeFrame.MediaAnalysis
  alias Defdo.KoeFrame.MediaAnalysis.MediaInfo

  defmodule RecordingAdapter do
    @behaviour Defdo.KoeFrame.MediaAnalysis.Adapter

    alias Defdo.KoeFrame.MediaAnalysis.MediaInfo

    @impl true
    def probe(source_path) do
      send(Process.get(:media_analysis_test_owner), {:probe, source_path})
      {:ok, %MediaInfo{streams: []}}
    end

    @impl true
    def extract_subtitle(source_path, stream_index, output_path, opts) do
      send(
        Process.get(:media_analysis_test_owner),
        {:extract_subtitle, source_path, stream_index, output_path, opts}
      )

      {:ok, output_path}
    end

    @impl true
    def extract_audio_segment(
          source_path,
          stream_index,
          start_ms,
          duration_ms,
          output_path,
          opts
        ) do
      send(
        Process.get(:media_analysis_test_owner),
        {:extract_audio_segment, source_path, stream_index, start_ms, duration_ms, output_path,
         opts}
      )

      {:ok, output_path}
    end
  end

  setup do
    previous_adapter = Application.get_env(:koe_frame, :media_analysis_adapter)
    Application.put_env(:koe_frame, :media_analysis_adapter, RecordingAdapter)
    Process.put(:media_analysis_test_owner, self())

    temp_dir =
      Path.join(
        System.tmp_dir!(),
        "koe-frame-media-analysis-#{System.unique_integer([:positive])}"
      )

    File.mkdir_p!(temp_dir)
    source_path = Path.join(temp_dir, "source.mkv")
    File.write!(source_path, "media")

    on_exit(fn ->
      if previous_adapter do
        Application.put_env(:koe_frame, :media_analysis_adapter, previous_adapter)
      else
        Application.delete_env(:koe_frame, :media_analysis_adapter)
      end

      File.rm_rf!(temp_dir)
    end)

    {:ok, source_path: source_path, temp_dir: temp_dir}
  end

  test "probe delegates through the configured adapter", %{source_path: source_path} do
    assert {:ok, %MediaInfo{streams: []}} = MediaAnalysis.probe(source_path)
    assert_receive {:probe, ^source_path}
  end

  test "extraction sends a validated stream and audio profile to the adapter", %{
    source_path: source_path,
    temp_dir: temp_dir
  } do
    subtitle_path = Path.join(temp_dir, "track.ass")

    assert {:ok, ^subtitle_path} = MediaAnalysis.extract_subtitle(source_path, 3, subtitle_path)
    assert_receive {:extract_subtitle, ^source_path, 3, ^subtitle_path, []}

    audio_path = Path.join(temp_dir, "sample.wav")

    assert {:ok, ^audio_path} =
             MediaAnalysis.extract_audio_segment(source_path, 1, 1_900, 20_000, audio_path)

    assert_receive {:extract_audio_segment, ^source_path, 1, 1_900, 20_000, ^audio_path,
                    [sample_rate: 16_000, channels: 1]}
  end

  test "accepts a 60-second millisecond segment and rejects longer or fractional values", %{
    source_path: source_path,
    temp_dir: temp_dir
  } do
    maximum_path = Path.join(temp_dir, "maximum.wav")

    assert {:ok, ^maximum_path} =
             MediaAnalysis.extract_audio_segment(source_path, 1, 60_000, 60_000, maximum_path)

    assert_receive {:extract_audio_segment, ^source_path, 1, 60_000, 60_000, ^maximum_path, _opts}

    too_long_path = Path.join(temp_dir, "too-long.wav")

    assert {:error, :segment_too_long} =
             MediaAnalysis.extract_audio_segment(
               source_path,
               1,
               0,
               3_600_000,
               too_long_path
             )

    assert {:error, :invalid_time_range} =
             MediaAnalysis.extract_audio_segment(source_path, 1, 0.5, 1_000, too_long_path)

    refute_receive {:extract_audio_segment, _, _, _, _, _, _}
  end

  test "rejects audio profiles outside the supported sample-rate and channel bounds", %{
    source_path: source_path,
    temp_dir: temp_dir
  } do
    output_path = Path.join(temp_dir, "valid-profile.wav")

    assert {:ok, ^output_path} =
             MediaAnalysis.extract_audio_segment(
               source_path,
               0,
               0,
               1_000,
               output_path,
               sample_rate: 192_000,
               channels: 8
             )

    assert_receive {:extract_audio_segment, _, _, _, _, _, [sample_rate: 192_000, channels: 8]}

    assert {:error, :invalid_audio_profile} =
             MediaAnalysis.extract_audio_segment(
               source_path,
               0,
               0,
               1_000,
               Path.join(temp_dir, "too-high-rate.wav"),
               sample_rate: 1_000_000_000,
               channels: 1
             )

    assert {:error, :invalid_audio_profile} =
             MediaAnalysis.extract_audio_segment(
               source_path,
               0,
               0,
               1_000,
               Path.join(temp_dir, "too-many-channels.wav"),
               sample_rate: 48_000,
               channels: 64
             )

    refute_receive {:extract_audio_segment, _, _, _, _, _, _}
  end

  test "rejects directories and missing sources with distinct stable errors", %{
    temp_dir: temp_dir
  } do
    directory = Path.join(temp_dir, "directory")
    File.mkdir_p!(directory)

    assert {:error, :source_not_regular_file} = MediaAnalysis.probe(directory)
    assert {:error, :source_file_not_found} = MediaAnalysis.probe(directory <> ".missing")

    refute_receive {:probe, _}
  end

  test "rejects a bad stream index before invoking the adapter", %{source_path: source_path} do
    assert {:error, :invalid_stream_index} =
             MediaAnalysis.extract_subtitle(
               source_path,
               -1,
               Path.join(System.tmp_dir!(), "out.ass")
             )

    refute_receive {:extract_subtitle, _, _, _, _}
  end
end
