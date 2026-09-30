defmodule Defdo.KoeFrame.MediaAnalysis do
  @moduledoc "KoeFrame-owned entry point for local media inventory and extraction."

  alias Defdo.KoeFrame.MediaAnalysis.{FfmpexAdapter, MediaInfo}

  @max_segment_ms 60_000
  @default_profile %{sample_rate: 16_000, channels: 1}

  @type error ::
          :source_file_not_found
          | :source_path_must_be_absolute
          | :source_not_regular_file
          | :invalid_stream_index
          | :invalid_time_range
          | :segment_too_long
          | :invalid_audio_profile
          | :invalid_output_format
          | :output_path_must_be_absolute
          | :output_directory_not_found
          | :output_already_exists
          | :probe_failed
          | :ffmpeg_unavailable
          | {:ffmpeg_failed, non_neg_integer()}
          | :output_not_created
          | :output_empty

  @doc "Probe a local media file and return normalized container and stream metadata."
  def probe(source_path) do
    with :ok <- validate_source(source_path) do
      call_adapter(:probe, [source_path], :probe_failed)
    end
  end

  @doc "Copy the selected subtitle stream to an absolute destination without overwriting it."
  @spec extract_subtitle(binary(), term(), binary(), binary() | nil) ::
          {:ok, binary()} | {:error, error()}
  def extract_subtitle(source_path, stream_index, output_path, output_format) do
    with :ok <- validate_source(source_path),
         :ok <- validate_stream_index(stream_index),
         :ok <- validate_output_format(output_format),
         :ok <- validate_output(output_path) do
      result =
        call_adapter(
          :extract_subtitle,
          [source_path, stream_index, output_path, output_format],
          :ffmpeg_failed
        )

      extraction_result(result, output_path)
    end
  end

  @doc "Extract a bounded WAV segment from one stream at the requested profile."
  @spec extract_audio_segment(binary(), term(), term(), term(), binary(), term()) ::
          {:ok, binary()} | {:error, error()}
  def extract_audio_segment(
        source_path,
        stream_index,
        start_ms,
        duration_ms,
        output_path,
        profile
      ) do
    with :ok <- validate_source(source_path),
         :ok <- validate_stream_index(stream_index),
         :ok <- validate_time_range(start_ms, duration_ms),
         :ok <- validate_segment_length(duration_ms),
         {:ok, normalized_profile} <- normalize_profile(profile),
         :ok <- validate_output(output_path) do
      result =
        call_adapter(
          :extract_audio_segment,
          [source_path, stream_index, start_ms, duration_ms, output_path, normalized_profile],
          :ffmpeg_failed
        )

      extraction_result(result, output_path)
    end
  end

  defp validate_source(path) when is_binary(path) do
    cond do
      Path.type(path) != :absolute -> {:error, :source_path_must_be_absolute}
      not File.exists?(path) -> {:error, :source_file_not_found}
      not File.regular?(path) -> {:error, :source_not_regular_file}
      true -> :ok
    end
  end

  defp validate_source(_path), do: {:error, :source_path_must_be_absolute}

  defp validate_stream_index(index) when is_integer(index) and index >= 0, do: :ok
  defp validate_stream_index(_index), do: {:error, :invalid_stream_index}

  defp validate_time_range(start_ms, duration_ms)
       when is_integer(start_ms) and start_ms >= 0 and is_integer(duration_ms) and duration_ms > 0,
       do: :ok

  defp validate_time_range(_start_ms, _duration_ms), do: {:error, :invalid_time_range}

  defp validate_segment_length(duration_ms) when duration_ms <= @max_segment_ms, do: :ok
  defp validate_segment_length(_duration_ms), do: {:error, :segment_too_long}

  defp validate_profile_values(sample_rate, channels)
       when is_integer(sample_rate) and sample_rate > 0 and is_integer(channels) and channels > 0,
       do: {:ok, %{sample_rate: sample_rate, channels: channels}}

  defp validate_profile_values(_sample_rate, _channels), do: {:error, :invalid_audio_profile}

  defp normalize_profile(nil), do: {:ok, @default_profile}
  defp normalize_profile(%{} = profile), do: normalize_profile_map(profile)

  defp normalize_profile(profile) when is_list(profile) do
    if Keyword.keyword?(profile) do
      normalize_profile_map(Map.new(profile))
    else
      {:error, :invalid_audio_profile}
    end
  end

  defp normalize_profile(_profile), do: {:error, :invalid_audio_profile}

  defp normalize_profile_map(profile) do
    if Map.keys(profile) -- [:sample_rate, :channels] == [] do
      validate_profile_values(
        Map.get(profile, :sample_rate, @default_profile.sample_rate),
        Map.get(profile, :channels, @default_profile.channels)
      )
    else
      {:error, :invalid_audio_profile}
    end
  end

  defp validate_output_format(nil), do: :ok

  defp validate_output_format(format) when is_binary(format) do
    if Regex.match?(~r/\A[a-zA-Z0-9_+-]+\z/, format) do
      :ok
    else
      {:error, :invalid_output_format}
    end
  end

  defp validate_output_format(_format), do: {:error, :invalid_output_format}

  defp validate_output(path) when is_binary(path) do
    cond do
      Path.type(path) != :absolute -> {:error, :output_path_must_be_absolute}
      not File.dir?(Path.dirname(path)) -> {:error, :output_directory_not_found}
      path_entry_exists?(path) -> {:error, :output_already_exists}
      true -> :ok
    end
  end

  defp validate_output(_path), do: {:error, :output_path_must_be_absolute}

  defp path_entry_exists?(path) do
    case File.lstat(path) do
      {:ok, _stat} -> true
      {:error, :enoent} -> false
      {:error, _reason} -> true
    end
  end

  defp call_adapter(function, arguments, fallback_error) do
    adapter = Application.get_env(:koe_frame, :media_analysis_adapter, FfmpexAdapter)

    result =
      try do
        apply(adapter, function, arguments)
      rescue
        _exception -> {:error, fallback_error}
      catch
        _kind, _reason -> {:error, fallback_error}
      end

    normalize_adapter_result(function, result)
  end

  defp normalize_adapter_result(:probe, {:ok, %MediaInfo{} = info}), do: {:ok, info}

  defp normalize_adapter_result(:probe, {:error, :ffmpeg_unavailable}),
    do: {:error, :ffmpeg_unavailable}

  defp normalize_adapter_result(:probe, _result), do: {:error, :probe_failed}

  defp normalize_adapter_result(_function, {:ok, result}), do: {:ok, result}

  defp normalize_adapter_result(_function, {:error, :ffmpeg_unavailable}),
    do: {:error, :ffmpeg_unavailable}

  defp normalize_adapter_result(_function, {:error, reason})
       when reason in [:output_already_exists, :output_not_created, :output_empty],
       do: {:error, reason}

  defp normalize_adapter_result(_function, {:error, {:ffmpeg_failed, status}})
       when is_integer(status) and status >= 0,
       do: {:error, {:ffmpeg_failed, status}}

  defp normalize_adapter_result(_function, _result), do: {:error, {:ffmpeg_failed, 1}}

  defp extraction_result({:ok, _result}, output_path), do: verify_output(output_path)
  defp extraction_result({:error, reason}, _output_path), do: {:error, reason}

  defp verify_output(path) do
    case File.stat(path) do
      {:ok, %{type: :regular, size: size}} when size > 0 -> {:ok, path}
      {:ok, %{type: :regular, size: 0}} -> {:error, :output_empty}
      _other -> {:error, :output_not_created}
    end
  end
end
