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

  test "converts selected subtitle streams to SRT with no overwrite" do
    command = FfmpexAdapter.subtitle_command("/tmp/source.mkv", 6, "/tmp/subtitle.srt", "srt")
    {_executable, args} = FFmpex.prepare(command)

    assert "-n" in args
    assert adjacent?(args, "-map", "0:6")
    assert adjacent?(args, "-c:s", "srt")
    assert adjacent?(args, "-f", "srt")
    assert List.last(args) == "/tmp/subtitle.srt"
    refute "-y" in args
  end

  test "keeps codec-copy behavior when no output format is requested" do
    command = FfmpexAdapter.subtitle_command("/tmp/source.mkv", 6, "/tmp/subtitle.ass", nil)
    {_executable, args} = FFmpex.prepare(command)

    assert "-n" in args
    assert adjacent?(args, "-map", "0:6")
    assert adjacent?(args, "-c:s", "copy")
    assert List.last(args) == "/tmp/subtitle.ass"
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

  test "audio output verification rejects a WAV header with no sample frames" do
    path = wav_path(<<>>)

    assert File.stat!(path).size == 78
    assert {:error, :output_empty} = FfmpexAdapter.verify_audio_output(path, 1)
  end

  test "audio output verification skips metadata and requires a complete PCM frame" do
    path = wav_path(<<0, 0, 0, 0>>)

    assert {:ok, ^path} = FfmpexAdapter.verify_audio_output(path, 2)
    assert {:error, :output_empty} = FfmpexAdapter.verify_audio_output(path, 3)
  end

  defp wav_path(data) do
    encoder = "Lavf59.27.100"
    encoder_size = byte_size(encoder)
    encoder_padding = if rem(encoder_size, 2) == 1, do: <<0>>, else: <<>>
    info_chunk = "ISFT" <> <<encoder_size::little-32>> <> encoder <> encoder_padding
    list_payload = "INFO" <> info_chunk
    list_chunk = "LIST" <> <<byte_size(list_payload)::little-32>> <> list_payload

    format =
      <<1::little-16, 1::little-16, 16_000::little-32, 32_000::little-32, 2::little-16,
        16::little-16>>

    format_chunk = "fmt " <> <<byte_size(format)::little-32>> <> format
    data_padding = if rem(byte_size(data), 2) == 1, do: <<0>>, else: <<>>
    data_chunk = "data" <> <<byte_size(data)::little-32>> <> data <> data_padding
    chunks = format_chunk <> list_chunk <> data_chunk
    riff_size = byte_size("WAVE" <> chunks)
    wave = "RIFF" <> <<riff_size::little-32>> <> "WAVE" <> chunks

    path =
      Path.join(
        System.tmp_dir!(),
        "koe-frame-media-analysis-output-#{System.unique_integer([:positive])}.wav"
      )

    File.write!(path, wave)
    on_exit(fn -> File.rm(path) end)
    path
  end

  defp adjacent?(list, first, second) do
    list
    |> Enum.chunk_every(2, 1, :discard)
    |> Enum.any?(&(&1 == [first, second]))
  end
end
