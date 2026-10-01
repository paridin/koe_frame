defmodule Defdo.KoeFrame.TranscriptReview.SpeachesAdapter do
  @moduledoc """
  Streams one extracted WAV clip to the configured private Speaches endpoint.

  Provider response bodies and endpoint details are never copied into returned
  errors.
  """

  @behaviour Defdo.KoeFrame.TranscriptReview.Adapter

  @default_model "deepdml/faster-whisper-large-v3-turbo-ct2"
  @default_timeout_ms 180_000
  @max_timeout_ms 300_000
  @transcription_path "/v1/audio/transcriptions"

  @impl true
  def configuration do
    with {:ok, endpoint} <- endpoint(),
         :ok <- validate_endpoint(endpoint),
         {:ok, model} <- model(),
         {:ok, _timeout_ms} <- timeout_ms() do
      {:ok, %{model: model}}
    end
  end

  @impl true
  def transcribe(wav_path, language, duration_ms)
      when is_binary(wav_path) and is_binary(language) and is_integer(duration_ms) do
    with {:ok, settings} <- settings(),
         :ok <- validate_language(language),
         :ok <- validate_audio_file(wav_path),
         :ok <- validate_duration(duration_ms),
         {:ok, response} <- request(settings, wav_path, language),
         {:ok, words} <- normalize_response(response, duration_ms) do
      {:ok, words}
    end
  end

  def transcribe(_wav_path, _language, _duration_ms), do: {:error, :invalid_transcription_request}

  defp settings do
    with {:ok, endpoint} <- endpoint(),
         :ok <- validate_endpoint(endpoint),
         {:ok, model} <- model(),
         {:ok, timeout_ms} <- timeout_ms() do
      {:ok,
       %{endpoint: String.trim_trailing(endpoint, "/"), model: model, timeout_ms: timeout_ms}}
    end
  end

  defp endpoint do
    case Application.get_env(:koe_frame, :speaches_base_url) do
      endpoint when is_binary(endpoint) and endpoint != "" -> {:ok, endpoint}
      _ -> {:error, :speaches_endpoint_not_configured}
    end
  end

  defp validate_endpoint(endpoint) do
    uri = URI.parse(endpoint)

    valid? =
      uri.scheme in ["http", "https"] and is_binary(uri.host) and uri.host != "" and
        is_nil(uri.userinfo) and is_nil(uri.query) and is_nil(uri.fragment) and
        uri.path in [nil, "", "/"]

    if valid?, do: :ok, else: {:error, :invalid_speaches_endpoint}
  end

  defp model do
    case Application.get_env(:koe_frame, :speaches_model, @default_model) do
      model when is_binary(model) and model != "" -> {:ok, model}
      _ -> {:error, :speaches_model_not_configured}
    end
  end

  defp timeout_ms do
    case Application.get_env(:koe_frame, :speaches_timeout_ms, @default_timeout_ms) do
      timeout when is_integer(timeout) and timeout >= 1 and timeout <= @max_timeout_ms ->
        {:ok, timeout}

      timeout when is_binary(timeout) ->
        case Integer.parse(timeout) do
          {integer, ""} when integer >= 1 and integer <= @max_timeout_ms -> {:ok, integer}
          _ -> {:error, :invalid_speaches_timeout}
        end

      _ ->
        {:error, :invalid_speaches_timeout}
    end
  end

  defp validate_language(language) do
    if Regex.match?(~r/\A[a-zA-Z]{2}\z/, language),
      do: :ok,
      else: {:error, :invalid_source_language}
  end

  defp validate_duration(duration_ms) when duration_ms > 0 and duration_ms <= 60_000, do: :ok
  defp validate_duration(_duration_ms), do: {:error, :invalid_transcription_request}

  defp validate_audio_file(path) do
    case File.stat(path) do
      {:ok, %{type: :regular, size: size}} when size > 0 -> :ok
      _ -> {:error, :audio_file_unavailable}
    end
  rescue
    _error -> {:error, :audio_file_unavailable}
  end

  defp request(settings, wav_path, language) do
    file_stream = File.stream!(wav_path, [], 64 * 1024)

    fields = [
      {"file", {file_stream, filename: "segment.wav", content_type: "audio/wav"}},
      {"model", settings.model},
      {"language", String.downcase(language)},
      {"response_format", "verbose_json"},
      {"timestamp_granularities[]", "word"}
    ]

    options = [
      form_multipart: fields,
      request_timeout: settings.timeout_ms,
      receive_timeout: settings.timeout_ms,
      connect_options: [timeout: settings.timeout_ms],
      max_retries: 0,
      retry: false,
      redirect: false
    ]

    options = add_test_plug(options)

    case Req.post(settings.endpoint <> @transcription_path, options) do
      {:ok, %{status: status} = response} when status in 200..299 ->
        {:ok, Map.get(response, :body)}

      {:ok, %{status: status}} when status in [401, 403] ->
        {:error, :speaches_unauthorized}

      {:ok, %{status: status}} ->
        {:error, {:speaches_http_error, status}}

      {:error, %Req.TransportError{reason: reason}} when reason in [:timeout, :connect_timeout] ->
        {:error, :speaches_timeout}

      {:error, _reason} ->
        {:error, :speaches_unavailable}
    end
  rescue
    error ->
      if Application.get_env(:koe_frame, :runtime_env, :prod) == :test,
        do: reraise(error, __STACKTRACE__),
        else: {:error, :speaches_unavailable}
  catch
    kind, reason ->
      if Application.get_env(:koe_frame, :runtime_env, :prod) == :test do
        :erlang.raise(kind, reason, __STACKTRACE__)
      else
        {:error, :speaches_unavailable}
      end
  end

  defp add_test_plug(options) do
    if Application.get_env(:koe_frame, :runtime_env, :prod) == :test do
      case Application.get_env(:koe_frame, :speaches_test_plug) do
        nil -> options
        plug -> Keyword.put(options, :plug, plug)
      end
    else
      options
    end
  end

  defp normalize_response(%{"words" => words}, duration_ms) when is_list(words) and words != [] do
    Enum.reduce_while(words, {:ok, []}, fn word, {:ok, acc} ->
      case normalize_word(word, duration_ms) do
        {:ok, normalized} -> {:cont, {:ok, [normalized | acc]}}
        {:error, _reason} = error -> {:halt, error}
      end
    end)
    |> case do
      {:ok, normalized} -> {:ok, Enum.reverse(normalized)}
      {:error, _reason} = error -> error
    end
  end

  defp normalize_response(%{"words" => []}, _duration_ms), do: {:error, :word_timestamps_missing}
  defp normalize_response(%{"words" => nil}, _duration_ms), do: {:error, :word_timestamps_missing}

  defp normalize_response(%{} = response, _duration_ms)
       when not is_map_key(response, "words"),
       do: {:error, :word_timestamps_missing}

  defp normalize_response(_response, _duration_ms), do: {:error, :invalid_speaches_response}

  defp normalize_word(%{"word" => text, "start" => start, "end" => ending}, duration_ms)
       when is_binary(text) and is_number(start) and is_number(ending) do
    start_ms = round(start * 1_000)
    end_ms = round(ending * 1_000)

    cond do
      not String.valid?(text) or String.trim(text) == "" ->
        {:error, :invalid_speaches_response}

      start_ms < 0 or start_ms >= duration_ms or end_ms < start_ms or end_ms > duration_ms ->
        {:error, :word_timestamp_outside_clip}

      true ->
        {:ok, %{text: text, start_ms: start_ms, end_ms: end_ms}}
    end
  end

  defp normalize_word(_word, _duration_ms), do: {:error, :invalid_speaches_response}
end
