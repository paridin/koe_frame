defmodule Defdo.KoeFrame.Admin.SpeechModels.CactusWhistleAdapter do
  @moduledoc "Runs the fixed Cactus Whistle experiment through its native `needle` runtime."

  @model_id "cactus/whistle"
  @model_file "whistle.cact"
  @languages ["en", "de", "fr", "es", "it", "nl", "pl"]
  @default_timeout_ms 1_800_000
  @max_timeout_ms 1_800_000
  @max_clip_seconds 30
  @safe_environment_variables ~w(PATH TMPDIR LANG LC_ALL LC_CTYPE CUDA_VISIBLE_DEVICES CUDA_HOME CUDA_PATH LD_LIBRARY_PATH DYLD_LIBRARY_PATH)

  def candidate do
    status = runtime_status()

    %{
      id: @model_id,
      key: "cactus:whistle",
      name: "Cactus Whistle",
      provider: :cactus,
      task: "automatic-speech-recognition",
      languages: @languages,
      installed?: status.installed?,
      runtime_configured?: status.runtime_configured?,
      installable?: status.installable?,
      comparison_available?: status.installed? and status.runtime_configured?,
      experimental?: true,
      japanese_supported?: false,
      lifecycle_stage: if(status.installed?, do: :installed_experimental, else: :experimental),
      promotion_blockers: [
        :japanese_not_in_published_languages,
        :representative_japanese_benchmark_required,
        :repeatable_quality_latency_results_required,
        :human_review_required
      ]
    }
  end

  def installed do
    candidate = candidate()

    if candidate.comparison_available?,
      do: {:ok, [candidate]},
      else: {:ok, []}
  end

  def download(@model_id) do
    with {:ok, settings} <- download_settings(),
         :ok <- File.mkdir_p(settings.model_dir),
         {:ok, _output} <- run(settings, ["download", "whistle", "--out", settings.model_dir]),
         true <- installed_file?(settings.model_path) do
      :ok
    else
      false -> {:error, :cactus_model_not_installed}
      {:error, _reason} = error -> error
      _other -> {:error, :cactus_unavailable}
    end
  rescue
    _exception -> {:error, :cactus_unavailable}
  catch
    :exit, _reason -> {:error, :cactus_unavailable}
  end

  def download(_model_id), do: {:error, :model_unavailable}

  def transcribe(audio_path, @model_id) when is_binary(audio_path) do
    with {:ok, settings} <- settings(),
         true <- installed_file?(settings.model_path),
         :ok <- validate_audio_path(audio_path),
         {:ok, normalized_path, cleanup_path} <- prepare_audio(audio_path) do
      try do
        with {:ok, output} <-
               run(settings, [
                 "--model",
                 settings.model_path,
                 "--audio",
                 normalized_path,
                 "--audio-word-timestamps"
               ]),
             {:ok, result} <- normalize_transcription(output) do
          {:ok, result}
        end
      after
        if cleanup_path, do: File.rm(cleanup_path)
      end
    else
      false -> {:error, :cactus_model_not_installed}
      {:error, _reason} = error -> error
      _other -> {:error, :cactus_unavailable}
    end
  rescue
    _exception -> {:error, :cactus_unavailable}
  catch
    :exit, _reason -> {:error, :cactus_unavailable}
  end

  def transcribe(_audio_path, _model_id), do: {:error, :model_unavailable}

  defp runtime_status do
    runtime = settings()
    downloader = download_settings()
    configured_model_dir = Application.get_env(:koe_frame, :cactus_whistle_model_dir)

    model_path =
      if is_binary(configured_model_dir) and Path.type(configured_model_dir) == :absolute,
        do: Path.join(Path.expand(configured_model_dir), @model_file)

    %{
      runtime_configured?: match?({:ok, _settings}, runtime),
      installable?: match?({:ok, _settings}, downloader),
      installed?: is_binary(model_path) and installed_file?(model_path)
    }
  end

  defp settings do
    executable = Application.get_env(:koe_frame, :cactus_whistle_runner)
    model_dir = Application.get_env(:koe_frame, :cactus_whistle_model_dir)
    timeout = Application.get_env(:koe_frame, :cactus_whistle_timeout_ms, @default_timeout_ms)

    with {:ok, executable} <- resolve_executable(executable),
         true <- is_binary(model_dir) and Path.type(model_dir) == :absolute,
         {:ok, timeout_ms} <- normalize_timeout(timeout) do
      expanded_dir = Path.expand(model_dir)

      {:ok,
       %{
         executable: executable,
         model_dir: expanded_dir,
         model_path: Path.join(expanded_dir, @model_file),
         timeout_ms: timeout_ms
       }}
    else
      _other -> {:error, :cactus_not_configured}
    end
  end

  defp download_settings do
    executable = Application.get_env(:koe_frame, :cactus_whistle_downloader)
    model_dir = Application.get_env(:koe_frame, :cactus_whistle_model_dir)
    timeout = Application.get_env(:koe_frame, :cactus_whistle_timeout_ms, @default_timeout_ms)

    with {:ok, executable} <- resolve_executable(executable),
         true <- is_binary(model_dir) and Path.type(model_dir) == :absolute,
         {:ok, timeout_ms} <- normalize_timeout(timeout) do
      expanded_dir = Path.expand(model_dir)

      {:ok,
       %{
         executable: executable,
         model_dir: expanded_dir,
         model_path: Path.join(expanded_dir, @model_file),
         timeout_ms: timeout_ms
       }}
    else
      _other -> {:error, :cactus_not_configured}
    end
  end

  defp resolve_executable(path) when is_binary(path) and path != "" do
    executable =
      if String.contains?(path, "/"),
        do: resolve_path_executable(path),
        else: System.find_executable(path)

    if is_binary(executable), do: {:ok, executable}, else: {:error, :cactus_not_configured}
  end

  defp resolve_executable(_path), do: {:error, :cactus_not_configured}

  defp resolve_path_executable(path) do
    expanded_path = Path.expand(path)
    if executable_file?(expanded_path), do: expanded_path
  end

  defp executable_file?(path) do
    case File.stat(path) do
      {:ok, %{type: :regular, mode: mode}} -> :erlang.band(mode, 0o111) != 0
      _other -> false
    end
  end

  defp normalize_timeout(timeout) when is_integer(timeout) and timeout in 1..@max_timeout_ms,
    do: {:ok, timeout}

  defp normalize_timeout(timeout) when is_binary(timeout) do
    case Integer.parse(timeout) do
      {value, ""} when value in 1..@max_timeout_ms -> {:ok, value}
      _ -> {:error, :invalid_cactus_timeout}
    end
  end

  defp normalize_timeout(_timeout), do: {:error, :invalid_cactus_timeout}

  defp run(settings, arguments) do
    task =
      Task.async(fn ->
        System.cmd(settings.executable, arguments,
          cd: settings.model_dir,
          env: command_environment(),
          stderr_to_stdout: true
        )
      end)

    case Task.yield(task, settings.timeout_ms) do
      {:ok, {output, 0}} ->
        {:ok, output}

      {:ok, {_output, _exit_code}} ->
        {:error, :cactus_command_failed}

      nil ->
        Task.shutdown(task, :brutal_kill)
        {:error, :cactus_timeout}
    end
  rescue
    _exception -> {:error, :cactus_unavailable}
  catch
    :exit, _reason -> {:error, :cactus_unavailable}
  end

  defp command_environment do
    inherited = System.get_env()

    inherited
    |> Map.new(fn {key, _value} -> {key, nil} end)
    |> Map.merge(Map.take(inherited, @safe_environment_variables))
    |> Enum.to_list()
  end

  defp installed_file?(path) do
    case File.stat(path) do
      {:ok, %{type: :regular, size: size}} when size > 0 -> true
      _other -> false
    end
  rescue
    _exception -> false
  end

  defp validate_audio_path(path) do
    case File.stat(path) do
      {:ok, %{type: :regular, size: size}} when size > 0 -> :ok
      _other -> {:error, :invalid_comparison_audio}
    end
  rescue
    _exception -> {:error, :invalid_comparison_audio}
  end

  defp prepare_audio(path) do
    with {:ok, %{duration: duration, streams: streams}} <-
           Defdo.KoeFrame.MediaAnalysis.probe(path),
         true <- is_number(duration) and duration > 0 and duration <= @max_clip_seconds,
         stream when is_map(stream) <- Enum.find(streams, &(&1.codec_type == "audio")),
         true <- is_integer(stream.index) and stream.index >= 0 do
      if stream.codec_name == "pcm_s16le" and stream.sample_rate == 16_000 and
           stream.channels == 1 do
        {:ok, path, nil}
      else
        normalize_audio(path, stream.index, round(duration * 1_000))
      end
    else
      false -> {:error, :invalid_comparison_audio}
      nil -> {:error, :invalid_comparison_audio}
      {:error, :ffmpeg_unavailable} -> {:error, :ffmpeg_unavailable}
      _other -> {:error, :invalid_comparison_audio}
    end
  rescue
    _exception -> {:error, :invalid_comparison_audio}
  end

  defp normalize_audio(path, stream_index, duration_ms) do
    output_path =
      Path.join(System.tmp_dir!(), "koe-frame-cactus-audio-#{Ecto.UUID.generate()}.wav")

    case Defdo.KoeFrame.MediaAnalysis.extract_audio_segment(
           path,
           stream_index,
           0,
           duration_ms,
           output_path,
           %{sample_rate: 16_000, channels: 1}
         ) do
      {:ok, _output} -> {:ok, output_path, output_path}
      {:error, :ffmpeg_unavailable} -> {:error, :ffmpeg_unavailable}
      {:error, _reason} -> {:error, :audio_normalization_failed}
    end
  end

  defp normalize_transcription(output) do
    with {:ok, body} <- decode_output(output),
         text when is_binary(text) <-
           Map.get(body, "audio_text") || Map.get(body, "text") || Map.get(body, "response"),
         true <- String.valid?(text) do
      words =
        body
        |> Map.get("audio_words", Map.get(body, "words", []))
        |> List.wrap()
        |> Enum.flat_map(&normalize_word/1)

      language = Map.get(body, "audio_language") || Map.get(body, "language")

      {:ok, %{text: text, words: words, language: language}}
    else
      _other -> {:error, :invalid_cactus_response}
    end
  end

  defp decode_output(output) when is_binary(output) do
    output
    |> String.split("\n", trim: true)
    |> Enum.reverse()
    |> Enum.find_value({:error, :invalid_cactus_response}, fn line ->
      case Jason.decode(String.trim(line)) do
        {:ok, body} when is_map(body) -> {:ok, body}
        _other -> nil
      end
    end)
  end

  defp normalize_word(%{"text" => text, "start" => start, "end" => ending})
       when is_binary(text) and is_number(start) and is_number(ending) and start >= 0 and
              ending >= start do
    [%{text: text, start_ms: round(start * 1_000), end_ms: round(ending * 1_000)}]
  end

  defp normalize_word(%{"word" => text, "start" => start, "end" => ending})
       when is_binary(text) and is_number(start) and is_number(ending) and start >= 0 and
              ending >= start do
    [%{text: text, start_ms: round(start * 1_000), end_ms: round(ending * 1_000)}]
  end

  defp normalize_word(_word), do: []
end
