defmodule Defdo.KoeFrame.MediaAnalysis.FfmpexAdapter do
  @moduledoc "FFmpex-backed media adapter for the KoeFrame media analysis contract."

  @behaviour Defdo.KoeFrame.MediaAnalysis.Adapter

  import Bitwise, only: [band: 2]
  import FFmpex
  use FFmpex.Options

  alias Defdo.KoeFrame.MediaAnalysis.MediaInfo

  @impl true
  def probe(source_path) do
    with :ok <- ensure_tool_available(:ffprobe),
         {:ok, format} <- FFprobe.format(source_path),
         {:ok, streams} <- FFprobe.streams(source_path),
         {:ok, media_info} <- MediaInfo.from_ffprobe(format, streams) do
      {:ok, media_info}
    else
      {:error, :ffmpeg_unavailable} = error -> error
      {:error, _reason} -> {:error, :probe_failed}
    end
  rescue
    _exception -> {:error, :probe_failed}
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
        start_ms,
        duration_ms,
        output_path,
        opts
      ) do
    command =
      build_audio_segment_command(
        source_path,
        stream_index,
        start_ms,
        duration_ms,
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
        start_ms,
        duration_ms,
        output_path,
        opts
      ) do
    sample_rate = Keyword.fetch!(opts, :sample_rate)
    channels = Keyword.fetch!(opts, :channels)

    input =
      %FFmpex.File{path: source_path}
      |> FFmpex.File.add_option(option_ss(format_milliseconds(start_ms)))

    new_command()
    |> add_global_option(option_n())
    |> add_global_option(option_v("error"))
    |> add_input_file(input)
    |> add_output_file(output_path)
    |> add_file_option(option_map("0:#{stream_index}"))
    |> add_file_option(option_t(format_milliseconds(duration_ms)))
    |> add_file_option(option_f("wav"))
    |> add_stream_specifier(stream_type: :audio)
    |> add_stream_option(option_c("pcm_s16le"))
    |> add_stream_option(option_ar(to_string(sample_rate)))
    |> add_stream_option(option_ac(to_string(channels)))
  end

  defp execute_to_path(command, output_path) do
    with :ok <- ensure_tool_available(:ffmpeg) do
      case execute(command) do
        {:ok, _output} ->
          output_result(output_path)

        {:error, {_diagnostic, exit_status}} when is_integer(exit_status) ->
          {:error, {:ffmpeg_failed, exit_status}}

        {:error, _reason} ->
          {:error, {:ffmpeg_failed, 1}}
      end
    end
  rescue
    _exception -> {:error, :ffmpeg_failed}
  end

  defp output_result(output_path) do
    case File.stat(output_path) do
      {:ok, %{type: :regular, size: size}} when size > 0 -> {:ok, output_path}
      {:ok, %{type: :regular}} -> {:error, :output_empty}
      _missing_or_non_regular -> {:error, :output_not_created}
    end
  end

  defp ensure_tool_available(:ffmpeg), do: ensure_tool_available(:ffmpeg, :ffmpeg_path, "ffmpeg")

  defp ensure_tool_available(:ffprobe),
    do: ensure_tool_available(:ffprobe, :ffprobe_path, "ffprobe")

  defp ensure_tool_available(_tool, config_key, executable_name) do
    configured_path = Application.get_env(:ffmpex, config_key)

    executable =
      case configured_path do
        nil -> System.find_executable(executable_name)
        path when is_binary(path) -> configured_executable(path)
        _invalid -> nil
      end

    if is_binary(executable) and executable_file?(executable),
      do: :ok,
      else: {:error, :ffmpeg_unavailable}
  end

  defp executable_file?(path) do
    case File.stat(path) do
      {:ok, %{type: :regular, mode: mode}} -> band(mode, 0o111) != 0
      _other -> false
    end
  end

  defp configured_executable(path) do
    cond do
      Path.type(path) == :absolute -> path
      String.contains?(path, "/") -> Path.expand(path)
      true -> System.find_executable(path)
    end
  end

  defp format_milliseconds(milliseconds) do
    whole_seconds = div(milliseconds, 1_000)
    fractional_ms = rem(milliseconds, 1_000)

    case fractional_ms do
      0 ->
        Integer.to_string(whole_seconds)

      value ->
        fraction =
          value |> Integer.to_string() |> String.pad_leading(3, "0") |> String.trim_trailing("0")

        Integer.to_string(whole_seconds) <> "." <> fraction
    end
  end
end
