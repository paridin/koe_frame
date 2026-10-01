defmodule Defdo.KoeFrame.MediaAnalysis do
  @moduledoc """
  KoeFrame's application-owned entry point for probing and extracting media.

  The configured adapter hides the FFmpeg implementation from localization
  workflows and tests.
  """

  alias Defdo.KoeFrame.MediaAnalysis.{FfmpexAdapter, MediaInfo}

  @type reason :: term()

  @spec probe(Path.t()) :: {:ok, MediaInfo.t()} | {:error, reason()}
  def probe(source_path) do
    with :ok <- validate_source(source_path) do
      adapter().probe(source_path)
    end
  end

  @spec extract_subtitle(Path.t(), non_neg_integer(), Path.t(), keyword()) ::
          {:ok, Path.t()} | {:error, reason()}
  def extract_subtitle(source_path, stream_index, output_path, opts \\ []) do
    with :ok <- validate_source(source_path),
         :ok <- validate_stream_index(stream_index),
         :ok <- validate_output(output_path) do
      adapter().extract_subtitle(source_path, stream_index, output_path, opts)
    end
  end

  @spec extract_audio_segment(
          Path.t(),
          non_neg_integer(),
          number(),
          number(),
          Path.t(),
          keyword()
        ) :: {:ok, Path.t()} | {:error, reason()}
  def extract_audio_segment(
        source_path,
        stream_index,
        start_seconds,
        duration_seconds,
        output_path,
        opts \\ []
      ) do
    sample_rate = Keyword.get(opts, :sample_rate, 16_000)
    channels = Keyword.get(opts, :channels, 1)

    with :ok <- validate_source(source_path),
         :ok <- validate_stream_index(stream_index),
         :ok <- validate_time_range(start_seconds, duration_seconds),
         :ok <- validate_audio_profile(sample_rate, channels),
         :ok <- validate_output(output_path) do
      adapter().extract_audio_segment(
        source_path,
        stream_index,
        start_seconds,
        duration_seconds,
        output_path,
        sample_rate: sample_rate,
        channels: channels
      )
    end
  end

  defp adapter do
    Application.get_env(:koe_frame, :media_analysis_adapter, FfmpexAdapter)
  end

  defp validate_source(source_path) when is_binary(source_path) do
    cond do
      Path.type(source_path) != :absolute -> {:error, :source_path_must_be_absolute}
      not File.regular?(source_path) -> {:error, :source_file_not_found}
      true -> :ok
    end
  end

  defp validate_source(_source_path), do: {:error, :source_path_must_be_absolute}

  defp validate_stream_index(index) when is_integer(index) and index >= 0, do: :ok
  defp validate_stream_index(_index), do: {:error, :invalid_stream_index}

  defp validate_time_range(start_seconds, duration_seconds)
       when is_number(start_seconds) and start_seconds >= 0 and is_number(duration_seconds) and
              duration_seconds > 0,
       do: :ok

  defp validate_time_range(_start_seconds, _duration_seconds), do: {:error, :invalid_time_range}

  defp validate_audio_profile(sample_rate, channels)
       when is_integer(sample_rate) and sample_rate > 0 and is_integer(channels) and channels > 0,
       do: :ok

  defp validate_audio_profile(_sample_rate, _channels), do: {:error, :invalid_audio_profile}

  defp validate_output(output_path) when is_binary(output_path) do
    cond do
      Path.type(output_path) != :absolute -> {:error, :output_path_must_be_absolute}
      not File.dir?(Path.dirname(output_path)) -> {:error, :output_directory_not_found}
      File.exists?(output_path) -> {:error, :output_already_exists}
      true -> :ok
    end
  end

  defp validate_output(_output_path), do: {:error, :output_path_must_be_absolute}
end
