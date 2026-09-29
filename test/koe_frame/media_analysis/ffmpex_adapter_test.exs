defmodule Defdo.KoeFrame.MediaAnalysis.FfmpexAdapterTest do
  use ExUnit.Case, async: true

  alias Defdo.KoeFrame.MediaAnalysis.{FfmpexAdapter, MediaInfo, MediaStream}

  test "normalizes string-keyed format and stream maps while preserving global indexes" do
    info =
      MediaInfo.from_ffprobe(
        %{"format_name" => "matroska,webm", "duration" => "91.125", "size" => "98765"},
        [
          %{
            "index" => 4,
            "codec_type" => "audio",
            "codec_name" => "aac",
            "sample_rate" => "48000",
            "channels" => 2,
            "tags" => %{"language" => "jpn", "title" => "Main"},
            "disposition" => %{"default" => 1, "forced" => 0, "attached_pic" => 0}
          },
          %{
            "index" => 8,
            "codec_type" => "video",
            "codec_name" => "mjpeg",
            "width" => 600,
            "height" => 600,
            "disposition" => %{"attached_pic" => 1}
          }
        ]
      )

    assert %MediaInfo{
             format_name: "matroska,webm",
             duration: 91.125,
             size: 98_765,
             streams: streams
           } = info

    assert [%MediaStream{} = audio, %MediaStream{} = cover] = streams

    assert audio == %MediaStream{
             index: 4,
             codec_type: "audio",
             codec_name: "aac",
             language: "jpn",
             title: "Main",
             default: true,
             forced: false,
             width: nil,
             height: nil,
             sample_rate: 48_000,
             channels: 2,
             attached_picture: false
           }

    assert cover.index == 8
    assert cover.width == 600
    assert cover.height == 600
    assert cover.attached_picture
    assert is_nil(cover.language)
    assert is_nil(cover.default)
    assert is_nil(cover.forced)
    assert is_nil(cover.sample_rate)
  end

  test "missing optional FFprobe metadata stays nil" do
    assert %MediaInfo{
             format_name: nil,
             duration: nil,
             size: nil,
             streams: [%MediaStream{} = stream]
           } =
             MediaInfo.from_ffprobe(%{}, [%{"index" => 0}])

    assert stream.index == 0
    assert is_nil(stream.codec_type)
    assert is_nil(stream.codec_name)
    assert is_nil(stream.language)
    assert is_nil(stream.title)
    assert is_nil(stream.default)
    assert is_nil(stream.forced)
    assert is_nil(stream.width)
    assert is_nil(stream.height)
    assert is_nil(stream.sample_rate)
    assert is_nil(stream.channels)
    assert is_nil(stream.attached_picture)
  end

  test "subtitle command maps and copies the requested subtitle stream with no overwrite" do
    command = FfmpexAdapter.subtitle_command("/tmp/source.mkv", 6, "/tmp/subtitle.srt", "srt")
    {_executable, args} = FFmpex.prepare(command)

    assert "-n" in args
    assert adjacent?(args, "-map", "0:6")
    assert adjacent?(args, "-c:s", "copy")
    assert adjacent?(args, "-f", "srt")
    assert List.last(args) == "/tmp/subtitle.srt"
    refute "-y" in args
  end

  test "audio command maps one stream and emits bounded WAV PCM at the requested profile" do
    command =
      FfmpexAdapter.audio_command(
        "/tmp/source.mkv",
        9,
        1_250,
        2_500,
        "/tmp/segment.wav",
        %{sample_rate: 22_050, channels: 2}
      )

    {_executable, args} = FFmpex.prepare(command)

    assert "-n" in args
    assert adjacent?(args, "-map", "0:9")
    assert adjacent?(args, "-ss", "1.25")
    assert adjacent?(args, "-t", "2.5")
    assert adjacent?(args, "-f", "wav")
    assert adjacent?(args, "-c:a", "pcm_s16le")
    assert adjacent?(args, "-ar:a", "22050")
    assert adjacent?(args, "-ac:a", "2")
    assert List.last(args) == "/tmp/segment.wav"
    refute "-y" in args
  end

  defp adjacent?(list, first, second) do
    list
    |> Enum.chunk_every(2, 1, :discard)
    |> Enum.any?(&(&1 == [first, second]))
  end
end
