defmodule Defdo.KoeFrame.Admin.SpeechModels.SpeachesAdapter do
  @moduledoc "Narrow server-side adapter for the Speaches model and transcription APIs."

  @default_timeout_ms 1_800_000
  @max_timeout_ms 1_800_000

  @type model :: %{id: String.t(), task: String.t(), languages: [String.t()]}

  def registry do
    with {:ok, settings} <- settings(),
         {:ok, body} <- request(:get, settings, "/v1/registry?task=automatic-speech-recognition"),
         {:ok, models} <- normalize_models(body) do
      {:ok, models}
    end
  end

  def installed do
    with {:ok, settings} <- settings(),
         {:ok, body} <- request(:get, settings, "/v1/models"),
         {:ok, models} <- normalize_models(body) do
      {:ok, models}
    end
  end

  def download(model_id) when is_binary(model_id) do
    with :ok <- validate_model_id(model_id),
         {:ok, settings} <- settings(),
         {:ok, _body} <- request(:post, settings, "/v1/models/#{encoded_model_id(model_id)}") do
      :ok
    end
  end

  def download(_model_id), do: {:error, :model_unavailable}

  def transcribe(audio_path, model_id) when is_binary(audio_path) and is_binary(model_id) do
    with :ok <- validate_model_id(model_id),
         {:ok, settings} <- settings(),
         :ok <- validate_audio_path(audio_path),
         {:ok, body} <- transcribe_request(settings, audio_path, model_id),
         {:ok, result} <- normalize_transcription(body) do
      {:ok, result}
    end
  end

  def transcribe(_audio_path, _model_id), do: {:error, :invalid_comparison_request}

  defp settings do
    endpoint = Application.get_env(:koe_frame, :speaches_base_url)

    timeout =
      Application.get_env(:koe_frame, :speaches_admin_timeout_ms, @default_timeout_ms)

    with true <- valid_endpoint?(endpoint),
         {:ok, timeout_ms} <- normalize_timeout(timeout) do
      {:ok, %{endpoint: String.trim_trailing(endpoint, "/"), timeout_ms: timeout_ms}}
    else
      false -> {:error, :speaches_endpoint_not_configured}
      {:error, _reason} = error -> error
    end
  end

  defp valid_endpoint?(endpoint) when is_binary(endpoint) and endpoint != "" do
    uri = URI.parse(endpoint)

    uri.scheme in ["http", "https"] and is_binary(uri.host) and uri.host != "" and
      is_nil(uri.userinfo) and is_nil(uri.query) and is_nil(uri.fragment) and
      uri.path in [nil, "", "/"]
  end

  defp valid_endpoint?(_endpoint), do: false

  defp normalize_timeout(timeout) when is_integer(timeout) and timeout in 1..@max_timeout_ms,
    do: {:ok, timeout}

  defp normalize_timeout(timeout) when is_binary(timeout) do
    case Integer.parse(timeout) do
      {value, ""} when value in 1..@max_timeout_ms -> {:ok, value}
      _ -> {:error, :invalid_speaches_timeout}
    end
  end

  defp normalize_timeout(_timeout), do: {:error, :invalid_speaches_timeout}

  defp request(method, settings, path) do
    options = request_options(settings)

    response =
      case method do
        :get -> Req.get(settings.endpoint <> path, options)
        :post -> Req.post(settings.endpoint <> path, Keyword.put(options, :json, %{}))
      end

    case response do
      {:ok, %{status: status, body: body}} when status in 200..299 ->
        {:ok, body}

      {:ok, %{status: status}} when status in [401, 403] ->
        {:error, :speaches_unauthorized}

      {:ok, %{status: status}} when status == 404 ->
        {:error, :model_unavailable}

      {:ok, _response} ->
        {:error, :speaches_unavailable}

      {:error, %Req.TransportError{reason: reason}}
      when reason in [:timeout, :connect_timeout] ->
        {:error, :speaches_timeout}

      {:error, _reason} ->
        {:error, :speaches_unavailable}
    end
  rescue
    _exception -> {:error, :speaches_unavailable}
  catch
    :exit, _reason -> {:error, :speaches_unavailable}
  end

  defp transcribe_request(settings, audio_path, model_id) do
    fields = [
      {"file",
       {File.stream!(audio_path, [], 64 * 1024),
        filename: "comparison.wav", content_type: "audio/wav"}},
      {"model", model_id},
      {"language", "ja"},
      {"response_format", "verbose_json"},
      {"timestamp_granularities[]", "word"}
    ]

    case Req.post(
           settings.endpoint <> "/v1/audio/transcriptions",
           Keyword.put(request_options(settings), :form_multipart, fields)
         ) do
      {:ok, %{status: status, body: body}} when status in 200..299 ->
        {:ok, body}

      {:ok, %{status: status}} when status in [401, 403] ->
        {:error, :speaches_unauthorized}

      {:ok, _response} ->
        {:error, :speaches_unavailable}

      {:error, %Req.TransportError{reason: reason}}
      when reason in [:timeout, :connect_timeout] ->
        {:error, :speaches_timeout}

      {:error, _reason} ->
        {:error, :speaches_unavailable}
    end
  rescue
    _exception -> {:error, :speaches_unavailable}
  catch
    :exit, _reason -> {:error, :speaches_unavailable}
  end

  defp request_options(settings) do
    [
      request_timeout: settings.timeout_ms,
      receive_timeout: settings.timeout_ms,
      connect_options: [timeout: settings.timeout_ms],
      max_retries: 0,
      retry: false,
      redirect: false
    ]
    |> add_test_plug()
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

  defp normalize_models(%{"data" => models}) when is_list(models), do: normalize_models(models)
  defp normalize_models(%{"models" => models}) when is_list(models), do: normalize_models(models)

  defp normalize_models(models) when is_list(models) do
    normalized = Enum.flat_map(models, &normalize_model/1)
    {:ok, Enum.uniq_by(normalized, & &1.id)}
  end

  defp normalize_models(_body), do: {:error, :invalid_speaches_response}

  defp normalize_model(%{"id" => id} = model) when is_binary(id) do
    with :ok <- validate_model_id(id) do
      task =
        Map.get(model, "task") || Map.get(model, "task_type") || "automatic-speech-recognition"

      languages =
        model
        |> Map.get("languages", Map.get(model, "language", []))
        |> List.wrap()
        |> Enum.filter(&is_binary/1)
        |> Enum.map(&String.downcase/1)

      [%{id: id, task: task, languages: languages}]
    else
      _ -> []
    end
  end

  defp normalize_model(_model), do: []

  defp normalize_transcription(%{"text" => text} = body) when is_binary(text) do
    if String.valid?(text) do
      words =
        body
        |> Map.get("words", [])
        |> List.wrap()
        |> Enum.flat_map(&normalize_word/1)

      {:ok, %{text: text, words: words}}
    else
      {:error, :invalid_speaches_response}
    end
  end

  defp normalize_transcription(%{"words" => words}) when is_list(words) do
    text =
      words
      |> Enum.flat_map(&normalize_word/1)
      |> Enum.map_join("", & &1.text)

    if text == "", do: {:error, :invalid_speaches_response}, else: {:ok, %{text: text, words: []}}
  end

  defp normalize_transcription(_body), do: {:error, :invalid_speaches_response}

  defp normalize_word(%{"word" => text, "start" => start, "end" => ending})
       when is_binary(text) and is_number(start) and is_number(ending) and start >= 0 and
              ending >= start do
    [%{text: text, start_ms: round(start * 1_000), end_ms: round(ending * 1_000)}]
  end

  defp normalize_word(_word), do: []

  defp validate_audio_path(path) do
    case File.stat(path) do
      {:ok, %{type: :regular, size: size}} when size > 0 -> :ok
      _ -> {:error, :invalid_comparison_audio}
    end
  rescue
    _exception -> {:error, :invalid_comparison_audio}
  end

  defp validate_model_id(model_id) do
    case String.split(model_id, "/") do
      [namespace, repository]
      when byte_size(namespace) in 1..96 and byte_size(repository) in 1..128 ->
        if namespace not in [".", ".."] and repository not in [".", ".."] and
             Regex.match?(~r/\A[A-Za-z0-9_.-]+\z/, namespace) and
             Regex.match?(~r/\A[A-Za-z0-9_.-]+\z/, repository),
           do: :ok,
           else: {:error, :model_unavailable}

      _ ->
        {:error, :model_unavailable}
    end
  end

  defp encoded_model_id(model_id) do
    model_id
    |> String.split("/")
    |> Enum.map_join("/", fn segment -> URI.encode(segment, &URI.char_unreserved?/1) end)
  end
end
