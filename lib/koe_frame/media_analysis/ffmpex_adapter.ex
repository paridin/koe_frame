defmodule Defdo.KoeFrame.MediaAnalysis.FfmpexAdapter do
  @moduledoc "Ffmpex-backed media probing and extraction adapter."

  use FFmpex.Options

  alias Defdo.KoeFrame.MediaAnalysis.MediaInfo

  @behaviour Defdo.KoeFrame.MediaAnalysis.Adapter

  @impl true
  def probe(source_path) do
    cond do
      not executable_available?(:ffprobe_path, "ffprobe") ->
        {:error, :ffmpeg_unavailable}

      true ->
        do_probe(source_path)
    end
  rescue
    _exception -> {:error, :probe_failed}
  catch
    _kind, _reason -> {:error, :probe_failed}
  end

  @impl true
  def extract_subtitle(source_path, stream_index, output_path, output_format) do
    execute_extraction(
      subtitle_command(source_path, stream_index, output_path, output_format),
      output_path
    )
  end

  @impl true
  def extract_audio_segment(
        source_path,
        stream_index,
        start_ms,
        duration_ms,
        output_path,
        profile
      ) do
    execute_extraction(
      audio_command(source_path, stream_index, start_ms, duration_ms, output_path, profile),
      output_path
    )
  end

  @doc false
  def subtitle_command(source_path, stream_index, output_path, output_format) do
    command =
      FFmpex.new_command()
      |> FFmpex.add_global_option(option_n())
      |> FFmpex.add_input_file(source_path)
      |> FFmpex.add_output_file(output_path)
      |> add_file_option("-map", "0:#{stream_index}")
      |> FFmpex.add_stream_specifier(stream_type: :subtitle)
      |> FFmpex.add_stream_option(option_c("copy"))

    case output_format do
      nil -> command
      format -> FFmpex.add_file_option(command, option_f(format))
    end
  end

  @doc false
  def audio_command(source_path, stream_index, start_ms, duration_ms, output_path, profile) do
    FFmpex.new_command()
    |> FFmpex.add_global_option(option_n())
    |> FFmpex.add_input_file(source_path)
    |> FFmpex.add_output_file(output_path)
    |> add_file_option("-map", "0:#{stream_index}")
    |> FFmpex.add_file_option(option_t(milliseconds_to_seconds(duration_ms)))
    |> FFmpex.add_file_option(option_ss(milliseconds_to_seconds(start_ms)))
    |> FFmpex.add_file_option(option_f("wav"))
    |> FFmpex.add_stream_specifier(stream_type: :audio)
    |> FFmpex.add_stream_option(option_c("pcm_s16le"))
    |> FFmpex.add_stream_option(option_ar(Integer.to_string(profile.sample_rate)))
    |> FFmpex.add_stream_option(option_ac(Integer.to_string(profile.channels)))
  end

  defp do_probe(source_path) do
    with {:ok, format} <- FFprobe.format(source_path),
         {:ok, streams} <- FFprobe.streams(source_path) do
      {:ok, MediaInfo.from_ffprobe(format, streams)}
    else
      _result -> {:error, :probe_failed}
    end
  end

  defp execute_extraction(command, output_path) do
    cond do
      not executable_available?(:ffmpeg_path, "ffmpeg") ->
        {:error, :ffmpeg_unavailable}

      path_entry_exists?(output_path) ->
        {:error, :output_already_exists}

      true ->
        execute_and_verify(command, output_path)
    end
  rescue
    _exception -> {:error, {:ffmpeg_failed, 1}}
  catch
    _kind, _reason -> {:error, {:ffmpeg_failed, 1}}
  end

  defp execute_and_verify(command, output_path) do
    case FFmpex.execute(command) do
      {:ok, _command_output} ->
        verify_output(output_path)

      {:error, {_command_output, status}} when is_integer(status) and status >= 0 ->
        {:error, {:ffmpeg_failed, status}}

      _other ->
        {:error, {:ffmpeg_failed, 1}}
    end
  end

  defp verify_output(path) do
    case File.stat(path) do
      {:ok, %{type: :regular, size: size}} when size > 0 -> {:ok, path}
      {:ok, %{type: :regular, size: 0}} -> {:error, :output_empty}
      _other -> {:error, :output_not_created}
    end
  end

  defp path_entry_exists?(path) do
    case File.lstat(path) do
      {:ok, _stat} -> true
      {:error, :enoent} -> false
      {:error, _reason} -> true
    end
  end

  defp executable_available?(config_key, executable) do
    case Application.get_env(:ffmpex, config_key) do
      nil -> not is_nil(System.find_executable(executable))
      path when is_binary(path) -> not is_nil(System.find_executable(path))
      _other -> false
    end
  end

  defp add_file_option(command, name, argument) do
    option = %FFmpex.Option{
      name: name,
      argument: argument,
      require_arg: true,
      contexts: [:output]
    }

    FFmpex.add_file_option(command, option)
  end

  defp milliseconds_to_seconds(milliseconds) do
    whole_seconds = div(milliseconds, 1_000)
    fractional = rem(milliseconds, 1_000)

    if fractional == 0 do
      Integer.to_string(whole_seconds)
    else
      fraction =
        fractional
        |> Integer.to_string()
        |> String.pad_leading(3, "0")
        |> String.trim_trailing("0")

      "#{whole_seconds}.#{fraction}"
    end
  end
end
