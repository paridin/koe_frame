defmodule Defdo.KoeFrame.MediaAnalysis.FfmpexAdapter do
  @moduledoc "FFmpex-backed media adapter for the KoeFrame media analysis contract."

  @behaviour Defdo.KoeFrame.MediaAnalysis.Adapter

  import FFmpex
  use FFmpex.Options

  alias Defdo.KoeFrame.MediaAnalysis.MediaInfo

  @impl true
  def probe(source_path) do
    with {:ok, format} <- FFprobe.format(source_path),
         {:ok, streams} <- FFprobe.streams(source_path),
         {:ok, media_info} <- MediaInfo.from_ffprobe(format, streams) do
      {:ok, media_info}
    end
  rescue
    _exception -> {:error, :media_probe_failed}
  end

  @impl true
  def extract_subtitle(source_path, stream_index, output_path, _opts) do
    command = build_subtitle_command(source_path, stream_index, output_path)
    execute_to_path(command, output_path)
  end

  @impl true
  def extract_audio_segment(
        source_path,
        stream_index,
        start_seconds,
        duration_seconds,
        output_path,
        opts
      ) do
    command =
      build_audio_segment_command(
        source_path,
        stream_index,
        start_seconds,
        duration_seconds,
        output_path,
        opts
      )

    execute_to_path(command, output_path)
  end

  @doc false
  def build_subtitle_command(source_path, stream_index, output_path) do
    new_command()
    |> add_global_option(option_n())
    |> add_global_option(option_v("error"))
    |> add_input_file(source_path)
    |> add_output_file(output_path)
    |> add_file_option(option_map("0:#{stream_index}"))
    |> add_stream_specifier(stream_type: :subtitle)
    |> add_stream_option(option_c("copy"))
  end

  @doc false
  def build_audio_segment_command(
        source_path,
        stream_index,
        start_seconds,
        duration_seconds,
        output_path,
        opts
      ) do
    sample_rate = Keyword.fetch!(opts, :sample_rate)
    channels = Keyword.fetch!(opts, :channels)

    input =
      %FFmpex.File{path: source_path}
      |> FFmpex.File.add_option(option_ss(format_seconds(start_seconds)))

    new_command()
    |> add_global_option(option_n())
    |> add_global_option(option_v("error"))
    |> add_input_file(input)
    |> add_output_file(output_path)
    |> add_file_option(option_map("0:#{stream_index}"))
    |> add_file_option(option_t(format_seconds(duration_seconds)))
    |> add_file_option(option_f("wav"))
    |> add_stream_specifier(stream_type: :audio)
    |> add_stream_option(option_c("pcm_s16le"))
    |> add_stream_option(option_ar(to_string(sample_rate)))
    |> add_stream_option(option_ac(to_string(channels)))
  end

  defp execute_to_path(command, output_path) do
    case execute(command) do
      {:ok, _output} ->
        if File.regular?(output_path) and File.stat!(output_path).size > 0 do
          {:ok, output_path}
        else
          {:error, :media_output_not_created}
        end

      {:error, {diagnostic, exit_status}} ->
        {:error, {:ffmpeg_failed, exit_status, diagnostic}}
    end
  rescue
    _exception -> {:error, :ffmpeg_failed}
  end

  defp format_seconds(seconds) when is_integer(seconds), do: Integer.to_string(seconds)
  defp format_seconds(seconds) when is_float(seconds), do: Float.to_string(seconds)
end
