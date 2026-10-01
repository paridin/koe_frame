defmodule Defdo.KoeFrame.MediaAnalysis.FfmpexAdapterTest do
  use ExUnit.Case, async: true

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
      FfmpexAdapter.build_audio_segment_command(source, 1, 190, 20, destination,
        sample_rate: 16_000,
        channels: 1
      )
      |> FFmpex.prepare()

    assert Enum.member?(args, source)
    assert Enum.member?(args, "0:1")
    assert Enum.member?(args, "-ss")
    assert Enum.member?(args, "190")
    assert Enum.member?(args, "-t")
    assert Enum.member?(args, "20")
    assert Enum.chunk_every(args, 2, 1, :discard) |> Enum.member?(["-c:a", "pcm_s16le"])
    assert Enum.chunk_every(args, 2, 1, :discard) |> Enum.member?(["-ar:a", "16000"])
    assert Enum.chunk_every(args, 2, 1, :discard) |> Enum.member?(["-ac:a", "1"])
    assert List.last(args) == destination
  end
end
