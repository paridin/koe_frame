defmodule Defdo.KoeFrame.TranscriptReview do
  @moduledoc """
  Builds a transient word-to-subtitle alignment preview for one local media clip.

  The caller must establish the tenant context before invoking preview/1.
  """

  alias Defdo.KoeFrame.MediaAnalysis
  alias Defdo.KoeFrame.MediaAnalysis.MediaStream
  alias Defdo.KoeFrame.Subtitler
  alias Defdo.KoeFrame.TranscriptReview.{Alignment, SpeachesAdapter}
  alias Defdo.Tenant.Context

  @max_clip_ms 60_000
  @max_srt_bytes 1_000_000
  @supported_subtitle_codecs ["ass", "ssa", "subrip"]
  @preview_keys [
    :path,
    :audio_stream,
    :subtitle_stream,
    :source_language,
    :start_ms,
    :duration_ms
  ]

  @doc "Returns media duration and FFprobe stream metadata with global stream indexes."
  @spec stream_inventory(Path.t()) :: {:ok, map()} | {:error, atom()}
  def stream_inventory(path) do
    with {:ok, info} <- MediaAnalysis.probe(path),
         {:ok, duration_ms} <- duration_ms(info.duration) do
      {:ok,
       %{
         format_name: info.format_name,
         duration_ms: duration_ms,
         size: info.size,
         streams: Enum.map(info.streams, &stream_map/1)
       }}
    end
  end

  @doc """
  Transcribes and aligns one bounded clip. The process tenant must be
  established at the calling edge because Subtitler credentials are resolved
  from Vault using that tenant.
  """
  @spec preview(map()) :: {:ok, map()} | {:error, atom() | tuple()}
  def preview(params) do
    with {:ok, request} <- validate_request(params),
         :ok <- require_tenant_context(),
         adapter <- adapter(),
         {:ok, adapter_config} <- adapter_configuration(adapter),
         {:ok, info} <- MediaAnalysis.probe(request.path),
         {:ok, media_duration_ms} <- duration_ms(info.duration),
         :ok <- validate_clip_end(request, media_duration_ms),
         {:ok, audio_stream} <- select_audio_stream(info.streams, request.audio_stream),
         {:ok, subtitle_stream} <- select_subtitle_stream(info.streams, request.subtitle_stream),
         {:ok, temp_dir} <- create_temp_dir() do
      run_with_temp_dir(temp_dir, fn ->
        build_preview(request, adapter, adapter_config, audio_stream, subtitle_stream, temp_dir)
      end)
    end
  end

  defp build_preview(request, adapter, adapter_config, audio_stream, subtitle_stream, temp_dir) do
    srt_path = Path.join(temp_dir, "subtitle.srt")
    audio_path = Path.join(temp_dir, "audio.wav")

    with {:ok, ^srt_path} <-
           MediaAnalysis.extract_subtitle(
             request.path,
             subtitle_stream.index,
             srt_path,
             "srt"
           ),
         {:ok, srt} <- read_srt(srt_path),
         {:ok, cues} <- Subtitler.normalize_srt(srt),
         :ok <- validate_cues(cues),
         {:ok, ^audio_path} <-
           MediaAnalysis.extract_audio_segment(
             request.path,
             audio_stream.index,
             request.start_ms,
             request.duration_ms,
             audio_path,
             nil
           ),
         {:ok, words} <-
           transcribe(adapter, audio_path, request.source_language, request.duration_ms) do
      alignment =
        Alignment.report(words, cues, request.start_ms, request.duration_ms)

      {:ok,
       Map.merge(alignment, %{
         source_language: request.source_language,
         model: adapter_config.model,
         audio_stream_index: audio_stream.index,
         subtitle_stream_index: subtitle_stream.index
       })}
    end
  end

  defp read_srt(path) do
    with {:ok, %{size: size}} <- File.stat(path),
         true <- size <= @max_srt_bytes,
         {:ok, content} <- File.read(path) do
      {:ok, content}
    else
      false -> {:error, :payload_too_large}
      _ -> {:error, :subtitle_file_unavailable}
    end
  rescue
    _error -> {:error, :subtitle_file_unavailable}
  end

  defp validate_cues(cues) when is_list(cues) and cues != [] do
    ids = Enum.map(cues, &Map.get(&1, :id))

    valid? =
      Enum.all?(cues, fn cue ->
        is_map(cue) and is_binary(Map.get(cue, :id)) and Map.get(cue, :id) != "" and
          is_integer(Map.get(cue, :start_ms)) and Map.get(cue, :start_ms) >= 0 and
          is_integer(Map.get(cue, :end_ms)) and Map.get(cue, :end_ms) > Map.get(cue, :start_ms) and
          is_binary(Map.get(cue, :text)) and String.valid?(Map.get(cue, :text)) and
          String.trim(Map.get(cue, :text)) != ""
      end)

    if valid? and length(ids) == length(Enum.uniq(ids)),
      do: :ok,
      else: {:error, :invalid_subtitler_response}
  rescue
    _error -> {:error, :invalid_subtitler_response}
  end

  defp validate_cues(_cues), do: {:error, :invalid_subtitler_response}

  defp transcribe(adapter, audio_path, language, duration_ms) do
    case adapter.transcribe(audio_path, language, duration_ms) do
      {:ok, words} -> validate_words(words, duration_ms)
      {:error, _reason} = error -> error
      _other -> {:error, :invalid_transcription_result}
    end
  rescue
    _error -> {:error, :speaches_unavailable}
  catch
    _kind, _reason -> {:error, :speaches_unavailable}
  end

  defp validate_words(words, duration_ms) when is_list(words) and words != [] do
    valid? =
      Enum.all?(words, fn word ->
        is_map(word) and is_binary(Map.get(word, :text)) and
          String.valid?(Map.get(word, :text)) and String.trim(Map.get(word, :text)) != "" and
          is_integer(Map.get(word, :start_ms)) and Map.get(word, :start_ms) >= 0 and
          Map.get(word, :start_ms) < duration_ms and
          is_integer(Map.get(word, :end_ms)) and
          Map.get(word, :end_ms) >= Map.get(word, :start_ms) and
          Map.get(word, :end_ms) <= duration_ms
      end)

    if valid?, do: {:ok, words}, else: {:error, :invalid_transcription_result}
  rescue
    _error -> {:error, :invalid_transcription_result}
  end

  defp validate_words(_words, _duration_ms), do: {:error, :word_timestamps_missing}

  defp adapter_configuration(adapter) do
    case adapter.configuration() do
      {:ok, %{model: model} = config} when is_binary(model) and model != "" ->
        {:ok, config}

      {:error, _reason} = error ->
        error

      _other ->
        {:error, :invalid_speaches_configuration}
    end
  rescue
    _error -> {:error, :invalid_speaches_configuration}
  catch
    _kind, _reason -> {:error, :invalid_speaches_configuration}
  end

  defp adapter do
    Application.get_env(:koe_frame, :transcript_review_adapter, SpeachesAdapter)
  end

  defp require_tenant_context do
    case Context.tenant_id() do
      tenant_id when is_binary(tenant_id) and tenant_id != "" -> :ok
      _ -> {:error, :missing_tenant_context}
    end
  end

  defp validate_request(params) when is_map(params) do
    if Enum.sort(Map.keys(params)) == Enum.sort(@preview_keys) do
      normalize_request(params)
    else
      {:error, :invalid_preview_request}
    end
  end

  defp validate_request(_params), do: {:error, :invalid_preview_request}

  defp normalize_request(params) do
    path = Map.get(params, :path)
    audio_stream = Map.get(params, :audio_stream)
    subtitle_stream = Map.get(params, :subtitle_stream)
    language = Map.get(params, :source_language)
    start_ms = Map.get(params, :start_ms)
    duration = Map.get(params, :duration_ms)

    cond do
      not is_binary(path) or Path.type(path) != :absolute ->
        {:error, :source_path_must_be_absolute}

      not File.exists?(path) ->
        {:error, :source_file_not_found}

      not File.regular?(path) ->
        {:error, :source_not_regular_file}

      not is_integer(audio_stream) or audio_stream < 0 ->
        {:error, :invalid_audio_stream}

      not is_integer(subtitle_stream) or subtitle_stream < 0 ->
        {:error, :invalid_subtitle_stream}

      not is_binary(language) or not Regex.match?(~r/\A[a-zA-Z]{2}\z/, language) ->
        {:error, :invalid_source_language}

      not is_integer(start_ms) or start_ms < 0 ->
        {:error, :invalid_time_range}

      not is_integer(duration) or duration < 1 ->
        {:error, :invalid_time_range}

      duration > @max_clip_ms ->
        {:error, :clip_too_long}

      true ->
        {:ok,
         %{
           path: path,
           audio_stream: audio_stream,
           subtitle_stream: subtitle_stream,
           source_language: String.downcase(language),
           start_ms: start_ms,
           duration_ms: duration
         }}
    end
  end

  defp validate_clip_end(request, media_duration_ms) do
    if request.start_ms + request.duration_ms <= media_duration_ms,
      do: :ok,
      else: {:error, :clip_outside_media}
  end

  defp select_audio_stream(streams, index) do
    case Enum.find(streams, &(&1.index == index)) do
      %MediaStream{codec_type: "audio"} = stream -> {:ok, stream}
      nil -> {:error, :audio_stream_not_found}
      _stream -> {:error, :invalid_audio_stream}
    end
  end

  defp select_subtitle_stream(streams, index) do
    case Enum.find(streams, &(&1.index == index)) do
      %MediaStream{codec_type: "subtitle", codec_name: codec} = stream
      when codec in @supported_subtitle_codecs ->
        {:ok, stream}

      %MediaStream{codec_type: "subtitle"} ->
        {:error, :unsupported_subtitle_codec}

      nil ->
        {:error, :subtitle_stream_not_found}

      _stream ->
        {:error, :invalid_subtitle_stream}
    end
  end

  defp duration_ms(duration) when is_number(duration) and duration > 0 do
    milliseconds = floor(duration * 1_000)
    if milliseconds > 0, do: {:ok, milliseconds}, else: {:error, :media_duration_unavailable}
  rescue
    _error -> {:error, :media_duration_unavailable}
  end

  defp duration_ms(_duration), do: {:error, :media_duration_unavailable}

  defp stream_map(%MediaStream{} = stream), do: Map.from_struct(stream)
  defp stream_map(_stream), do: %{}

  defp create_temp_dir do
    random = :crypto.strong_rand_bytes(18) |> Base.url_encode64(padding: false)
    path = Path.join(System.tmp_dir!(), "koe-frame-transcript-review-#{random}")

    case File.mkdir(path) do
      :ok ->
        case File.chmod(path, 0o700) do
          :ok ->
            {:ok, path}

          {:error, _reason} ->
            _ = File.rm_rf(path)
            {:error, :temporary_directory_unavailable}
        end

      {:error, _reason} ->
        {:error, :temporary_directory_unavailable}
    end
  rescue
    _error -> {:error, :temporary_directory_unavailable}
  end

  defp run_with_temp_dir(path, fun) do
    result =
      try do
        fun.()
      rescue
        _error -> {:error, :transcript_review_failed}
      catch
        _kind, _reason -> {:error, :transcript_review_failed}
      end

    case File.rm_rf(path) do
      {:ok, _removed} -> result
      {:error, _reason, _path} -> {:error, :temporary_cleanup_failed}
    end
  end
end
