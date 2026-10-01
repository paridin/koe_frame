defmodule Defdo.KoeFrame.MediaAnalysis.FfmpexAdapterTest do
  use ExUnit.Case, async: false

  alias Defdo.KoeFrame.MediaAnalysis.{FfmpexAdapter, MediaInfo, MediaStream}

  test "normalizes the format and stream facts used by KoeFrame" do
    assert {:ok,
            %MediaInfo{
              format_name: "matroska,webm",
              duration_seconds: 1421.984,
              size_bytes: 249_351_100,
              streams: [
                %MediaStream{
                  index: 3,
                  media_type: "subtitle",
                  codec_name: "ass",
                  language: "spa",
                  title: "Spanish",
                  default?: false,
                  forced?: false
                }
              ]
            }} =
             MediaInfo.from_ffprobe(
               %{
                 "format_name" => "matroska,webm",
                 "duration" => "1421.984",
                 "size" => "249351100"
               },
               [
                 %{
                   "index" => 3,
                   "codec_type" => "subtitle",
                   "codec_name" => "ass",
                   "tags" => %{"language" => "spa", "title" => "Spanish"},
                   "disposition" => %{"default" => 0, "forced" => 0}
                 }
               ]
             )
  end

  test "rejects probe data without a usable stream index" do
    assert {:error, :invalid_probe_result} =
             MediaInfo.from_ffprobe(%{}, [%{"codec_type" => "audio"}])
  end

  test "subtitle command maps only the selected stream and copies its codec" do
    source = "/media/anime/Aoyama episode.mkv"
    destination = "/tmp/Aoyama Spanish.ass"

    {_executable, args} =
      FfmpexAdapter.build_subtitle_command(source, 3, destination) |> FFmpex.prepare()

    assert Enum.member?(args, "-n")
    assert Enum.member?(args, source)
    assert Enum.member?(args, "0:3")
    assert Enum.chunk_every(args, 2, 1, :discard) |> Enum.member?(["-c:s", "copy"])
    assert List.last(args) == destination
  end

  test "audio command preserves stream selection and requests a mono 16 kHz WAV" do
    source = "/media/anime/Aoyama episode.mkv"
    destination = "/tmp/Aoyama sample.wav"

    {_executable, args} =
      FfmpexAdapter.build_audio_segment_command(source, 1, 190, 20_000, destination,
        sample_rate: 16_000,
        channels: 1
      )
      |> FFmpex.prepare()

    assert Enum.member?(args, source)
    assert Enum.member?(args, "0:1")
    assert Enum.member?(args, "-ss")
    assert Enum.member?(args, "0.19")
    assert Enum.member?(args, "-t")
    assert Enum.member?(args, "20")
    assert Enum.chunk_every(args, 2, 1, :discard) |> Enum.member?(["-c:a", "pcm_s16le"])
    assert Enum.chunk_every(args, 2, 1, :discard) |> Enum.member?(["-ar:a", "16000"])
    assert Enum.chunk_every(args, 2, 1, :discard) |> Enum.member?(["-ac:a", "1"])
    assert List.last(args) == destination
  end

  test "normalizes FFmpeg failures without returning stderr or private media paths" do
    temp_dir = temp_dir!()
    on_exit(fn -> File.rm_rf!(temp_dir) end)
    source = Path.join(temp_dir, "secret-series-name-episode.mkv")
    File.write!(source, "private media bytes")
    output = Path.join(temp_dir, "track.ass")
    executable = executable!(temp_dir, "ffmpeg", "printf '%s\\n' \"$@\" >&2\nexit 23\n")

    result =
      with_config(:ffmpeg_path, executable, fn ->
        FfmpexAdapter.extract_subtitle(source, 0, output, [])
      end)

    assert {:error, {:ffmpeg_failed, 23}} = result
    refute inspect(result) =~ source
  end

  test "reports missing FFmpeg and failed FFprobe with stable errors" do
    temp_dir = temp_dir!()
    on_exit(fn -> File.rm_rf!(temp_dir) end)
    source = Path.join(temp_dir, "episode.mkv")
    File.write!(source, "private media bytes")
    missing_ffmpeg = Path.join(temp_dir, "missing-ffmpeg")
    output = Path.join(temp_dir, "track.ass")

    assert {:error, :ffmpeg_unavailable} =
             with_config(:ffmpeg_path, missing_ffmpeg, fn ->
               FfmpexAdapter.extract_subtitle(source, 0, output, [])
             end)

    ffprobe = executable!(temp_dir, "ffprobe", "printf '%s\\n' \"$@\" >&2\nexit 19\n")

    assert {:error, :probe_failed} =
             with_config(:ffprobe_path, ffprobe, fn ->
               FfmpexAdapter.probe(source)
             end)
  end

  defp temp_dir! do
    path = Path.join(System.tmp_dir!(), "koe-frame-ffmpex-#{System.unique_integer([:positive])}")
    File.mkdir_p!(path)
    path
  end

  defp executable!(directory, name, body) do
    path = Path.join(directory, name)
    File.write!(path, "#!/bin/sh\n" <> body)
    File.chmod!(path, 0o700)
    path
  end

  defp with_config(key, value, fun) do
    previous = Application.get_env(:ffmpex, key)
    Application.put_env(:ffmpex, key, value)

    try do
      fun.()
    after
      if is_nil(previous),
        do: Application.delete_env(:ffmpex, key),
        else: Application.put_env(:ffmpex, key, previous)
    end
  end
end
