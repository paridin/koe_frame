defmodule Defdo.KoeFrame.Subtitler.HTTPAdapter do
  @moduledoc """
  HTTP adapter for Subtitler's transient SRT normalization endpoint.

  Requests carry subtitle text only, use a Vault-backed bearer token, and do
  not follow redirects. Responses are byte-limited while streaming and errors
  returned to callers never include response bodies, credentials, or subtitle
  text.
  """

  @behaviour Defdo.KoeFrame.Subtitler.Adapter

  alias Defdo.KoeFrame.Subtitler.VaultTokenProvider

  @max_cues 20_000
  @max_response_bytes 8 * 1024 * 1024
  @default_timeout_ms 30_000
  @cue_path "/api/cues/parse"
  @response_chunks_key :koe_frame_subtitler_response_chunks
  @response_size_key :koe_frame_subtitler_response_size
  @response_too_large_key :koe_frame_subtitler_response_too_large

  @server_errors %{
    "empty_srt" => :empty_srt,
    "malformed_srt" => :malformed_srt,
    "payload_too_large" => :payload_too_large,
    "too_many_cues" => :too_many_cues,
    "unsupported_format" => :unsupported_format,
    "invalid_request" => :invalid_request
  }

  @impl true
  def normalize_srt(content) when is_binary(content) do
    with {:ok, endpoint} <- endpoint_url(),
         :ok <- validate_endpoint_security(endpoint),
         {:ok, token} <- credential_provider().fetch_token(),
         {:ok, response} <- request(endpoint, token, content) do
      handle_response(response)
    else
      {:error, reason}
      when reason in [
             :credential_not_configured,
             :credential_unavailable,
             :endpoint_not_configured,
             :insecure_endpoint,
             :invalid_response,
             :missing_tenant_context,
             :response_too_large
           ] ->
        {:error, reason}

      {:error, _reason} ->
        {:error, :service_unavailable}
    end
  end

  defp request(endpoint, token, content) do
    timeout = Application.get_env(:koe_frame, :subtitler_cue_timeout_ms, @default_timeout_ms)

    request_options = [
      json: %{"format" => "srt", "content" => content},
      auth: {:bearer, token},
      retry: false,
      redirect: false,
      receive_timeout: timeout,
      connect_options: [timeout: timeout],
      decode_body: false,
      into: &collect_response_chunk/2
    ]

    request_options = add_test_plug(request_options)

    case Req.post(String.trim_trailing(endpoint, "/") <> @cue_path, request_options) do
      {:ok, response} -> decode_limited_response(response)
      {:error, _reason} -> {:error, :transport_error}
    end
  rescue
    _error -> {:error, :transport_error}
  end

  defp collect_response_chunk({:data, chunk}, {request, response}) do
    current_size = Map.get(response.private, @response_size_key, 0)

    if current_size + byte_size(chunk) > @max_response_bytes do
      private = Map.put(response.private, @response_too_large_key, true)
      {:halt, {request, %{response | private: private}}}
    else
      chunks = [chunk | Map.get(response.private, @response_chunks_key, [])]

      private =
        response.private
        |> Map.put(@response_chunks_key, chunks)
        |> Map.put(@response_size_key, current_size + byte_size(chunk))

      {:cont, {request, %{response | private: private}}}
    end
  end

  defp decode_limited_response(%{private: private, status: status}) do
    cond do
      Map.get(private, @response_too_large_key, false) ->
        {:error, :response_too_large}

      status not in [200, 400, 413] ->
        {:ok, %{status: status, body: %{}}}

      true ->
        body =
          private
          |> Map.get(@response_chunks_key, [])
          |> Enum.reverse()
          |> IO.iodata_to_binary()

        case Jason.decode(body) do
          {:ok, decoded_body} -> {:ok, %{status: status, body: decoded_body}}
          {:error, _reason} -> {:error, :invalid_response}
        end
    end
  end

  defp add_test_plug(request_options) do
    if Application.get_env(:koe_frame, :runtime_env, :prod) == :test do
      case Application.get_env(:koe_frame, :subtitler_cue_test_plug) do
        nil -> request_options
        plug -> Keyword.put(request_options, :plug, plug)
      end
    else
      request_options
    end
  end

  defp handle_response(%{status: 200, body: %{"cues" => cues}}) do
    validate_cues(cues)
  end

  defp handle_response(%{status: 200}), do: {:error, :invalid_response}

  defp handle_response(%{status: 401}), do: {:error, :unauthorized}
  defp handle_response(%{status: 503}), do: {:error, :service_unavailable}

  defp handle_response(%{status: status, body: %{"error" => %{"code" => code}}})
       when status in [400, 413] do
    case Map.fetch(@server_errors, code) do
      {:ok, reason} -> {:error, reason}
      :error -> {:error, :service_error}
    end
  end

  defp handle_response(%{status: _status}), do: {:error, :service_error}

  defp validate_cues(cues)
       when is_list(cues) and length(cues) > 0 and length(cues) <= @max_cues do
    cues
    |> Enum.with_index(1)
    |> Enum.reduce_while({:ok, []}, fn {cue, index}, {:ok, acc} ->
      case validate_cue(cue, index) do
        {:ok, normalized} -> {:cont, {:ok, [normalized | acc]}}
        {:error, _reason} = error -> {:halt, error}
      end
    end)
    |> case do
      {:ok, normalized} -> {:ok, Enum.reverse(normalized)}
      {:error, _reason} = error -> error
    end
  end

  defp validate_cues(_cues), do: {:error, :invalid_response}

  defp validate_cue(cue, index) when is_map(cue) do
    expected_keys = ["end_ms", "id", "start_ms", "text"]

    with true <- Enum.sort(Map.keys(cue)) == expected_keys,
         expected_id = "cue-#{index}",
         ^expected_id <- Map.get(cue, "id"),
         start_ms when is_integer(start_ms) and start_ms >= 0 <- Map.get(cue, "start_ms"),
         end_ms when is_integer(end_ms) and end_ms > start_ms <- Map.get(cue, "end_ms"),
         text when is_binary(text) <- Map.get(cue, "text"),
         true <- String.valid?(text) and String.trim(text) != "" do
      {:ok, %{id: expected_id, start_ms: start_ms, end_ms: end_ms, text: text}}
    else
      _ -> {:error, :invalid_response}
    end
  end

  defp validate_cue(_cue, _index), do: {:error, :invalid_response}

  defp endpoint_url do
    case Application.get_env(:koe_frame, :subtitler_cue_base_url) do
      endpoint when is_binary(endpoint) and endpoint != "" -> {:ok, endpoint}
      _ -> {:error, :endpoint_not_configured}
    end
  end

  defp validate_endpoint_security(endpoint) do
    runtime_env = Application.get_env(:koe_frame, :runtime_env, :prod)
    uri = URI.parse(endpoint)

    valid_uri? =
      is_binary(uri.host) and uri.host != "" and is_nil(uri.userinfo) and is_nil(uri.query) and
        is_nil(uri.fragment) and uri.path in [nil, "", "/"]

    secure? = uri.scheme == "https"
    local_http? = uri.scheme == "http" and runtime_env in [:dev, :test]

    if valid_uri? and (secure? or local_http?), do: :ok, else: {:error, :insecure_endpoint}
  end

  defp credential_provider do
    Application.get_env(:koe_frame, :subtitler_credential_provider, VaultTokenProvider)
  end
end
