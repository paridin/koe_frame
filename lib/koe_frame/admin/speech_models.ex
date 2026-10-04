defmodule Defdo.KoeFrame.Admin.SpeechModels do
  @moduledoc "Admin use cases for evaluating ASR models across isolated provider adapters."

  alias Defdo.KoeFrame.Admin.SpeechModels.CactusWhistleAdapter
  alias Defdo.KoeFrame.Admin.SpeechModels.SpeachesAdapter
  alias Defdo.KoeFrame.MediaAnalysis

  @max_audio_bytes 25_000_000
  @max_clip_seconds 30
  @min_comparison_models 2
  @max_comparison_models 4
  @max_reference_graphemes 5_000

  @type model :: %{id: String.t(), languages: [String.t()], installed?: boolean()}

  @spec inventory() ::
          {:ok,
           %{
             installed: [model()],
             candidates: [model()],
             experimental_candidates: [map()],
             experimental_installed: [map()],
             speaches_available?: boolean(),
             default_model: String.t()
           }}
          | {:error, atom()}
  def inventory do
    cactus_candidate = cactus_adapter().candidate()

    speaches_models = speaches_inventory()

    {installed, candidates, speaches_available?} =
      case speaches_models do
        {:ok, installed, candidates} -> {installed, candidates, true}
        {:error, _reason} -> {[], [], false}
      end

    experimental_installed =
      if cactus_candidate.comparison_available?,
        do: [cactus_candidate],
        else: []

    {:ok,
     %{
       installed: installed,
       candidates: candidates,
       experimental_candidates: [cactus_candidate],
       experimental_installed: experimental_installed,
       speaches_available?: speaches_available?,
       default_model: Application.get_env(:koe_frame, :speaches_model, default_model())
     }}
  rescue
    _exception -> {:error, :speech_model_inventory_unavailable}
  catch
    :exit, _reason -> {:error, :speech_model_inventory_unavailable}
  end

  @spec download(String.t()) :: :ok | {:error, atom()}
  def download("cactus:whistle"), do: download_cactus_whistle()

  def download(model_id) when is_binary(model_id) do
    case inventory() do
      {:ok, current} ->
        cond do
          not Enum.any?(current.candidates, &(&1.id == model_id)) ->
            {:error, :model_unavailable}

          Enum.any?(current.installed, &(&1.id == model_id)) ->
            {:error, :model_already_installed}

          true ->
            download_and_verify(model_id)
        end

      {:error, _reason} ->
        {:error, :speaches_unavailable}
    end
  rescue
    _exception -> {:error, :speaches_unavailable}
  catch
    :exit, _reason -> {:error, :speaches_unavailable}
  end

  def download(_model_id), do: {:error, :model_unavailable}

  @spec compare(Path.t(), [String.t()], String.t() | nil) ::
          {:ok, [map()]} | {:error, atom()}
  def compare(audio_path, model_ids, reference_text \\ nil)

  def compare(audio_path, model_ids, reference_text)
      when is_binary(audio_path) and is_list(model_ids) do
    with :ok <- validate_reference(reference_text),
         :ok <- validate_audio(audio_path),
         {:ok, inventory} <- inventory(),
         {:ok, selected} <-
           selected_models(inventory.installed ++ inventory.experimental_installed, model_ids) do
      results = Enum.map(selected, &compare_model(audio_path, &1, reference_text))
      {:ok, results}
    end
  rescue
    exception ->
      if Application.get_env(:koe_frame, :runtime_env, :prod) == :test,
        do: reraise(exception, __STACKTRACE__),
        else: {:error, :comparison_unavailable}
  catch
    kind, reason ->
      if Application.get_env(:koe_frame, :runtime_env, :prod) == :test,
        do: :erlang.raise(kind, reason, __STACKTRACE__),
        else: {:error, :comparison_unavailable}
  end

  def compare(_audio_path, _model_ids, _reference_text),
    do: {:error, :invalid_comparison_request}

  defp compare_model(audio_path, model, reference_text) do
    started_at = System.monotonic_time()
    result = transcribe(model, audio_path)

    elapsed_ms =
      System.convert_time_unit(System.monotonic_time() - started_at, :native, :millisecond)

    case result do
      {:ok, %{text: text, words: words} = transcription} ->
        %{
          key: model.key,
          id: model.id,
          provider: model.provider,
          language: Map.get(transcription, :language),
          japanese_supported?: model.japanese_supported?,
          lifecycle_stage: model.lifecycle_stage,
          promotion_blockers: model.promotion_blockers,
          status: :ok,
          transcript: text,
          word_count: length(words),
          elapsed_ms: elapsed_ms,
          character_error_rate: character_error_rate(reference_text, text),
          error: nil
        }

      {:error, reason} ->
        %{
          key: model.key,
          id: model.id,
          provider: model.provider,
          language: nil,
          japanese_supported?: model.japanese_supported?,
          lifecycle_stage: model.lifecycle_stage,
          promotion_blockers: model.promotion_blockers,
          status: :error,
          transcript: nil,
          word_count: 0,
          elapsed_ms: elapsed_ms,
          character_error_rate: nil,
          error: safe_error(reason)
        }

      _other ->
        %{
          key: model.key,
          id: model.id,
          provider: model.provider,
          language: nil,
          japanese_supported?: model.japanese_supported?,
          lifecycle_stage: model.lifecycle_stage,
          promotion_blockers: model.promotion_blockers,
          status: :error,
          transcript: nil,
          word_count: 0,
          elapsed_ms: elapsed_ms,
          character_error_rate: nil,
          error: :speaches_unavailable
        }
    end
  end

  defp download_and_verify(model_id) do
    with :ok <- adapter().download(model_id),
         {:ok, refreshed} <- inventory(),
         true <- Enum.any?(refreshed.installed, &(&1.id == model_id)) do
      :ok
    else
      false -> {:error, :model_not_installed}
      {:error, :speaches_timeout} -> {:error, :speaches_timeout}
      {:error, _reason} -> {:error, :speaches_unavailable}
      _other -> {:error, :speaches_unavailable}
    end
  end

  defp speaches_inventory do
    with {:ok, registered} <- adapter().registry(),
         {:ok, installed} <- adapter().installed() do
      registered_by_id = Map.new(registered, &{&1.id, &1})
      installed_ids = MapSet.new(Enum.map(installed, & &1.id))

      candidates =
        registered
        |> Enum.filter(&japanese_asr?/1)
        |> Enum.map(&model(&1, MapSet.member?(installed_ids, &1.id), :speaches))
        |> Enum.sort_by(& &1.id)

      installed_models =
        installed
        |> Enum.flat_map(fn installed_model ->
          metadata = Map.get(registered_by_id, installed_model.id, installed_model)

          if japanese_asr?(metadata),
            do: [model(metadata, true, :speaches)],
            else: []
        end)
        |> Enum.sort_by(& &1.id)

      {:ok, installed_models, candidates}
    else
      {:error, _reason} -> {:error, :speaches_unavailable}
      _other -> {:error, :speaches_unavailable}
    end
  rescue
    _exception -> {:error, :speaches_unavailable}
  catch
    :exit, _reason -> {:error, :speaches_unavailable}
  end

  defp download_cactus_whistle do
    candidate = cactus_adapter().candidate()

    cond do
      not candidate.installable? ->
        {:error, :cactus_not_configured}

      candidate.installed? ->
        {:error, :model_already_installed}

      true ->
        with :ok <- cactus_adapter().download(candidate.id),
             refreshed <- cactus_adapter().candidate(),
             true <- refreshed.installed? do
          :ok
        else
          false -> {:error, :model_not_installed}
          {:error, _reason} -> {:error, :cactus_unavailable}
          _other -> {:error, :cactus_unavailable}
        end
    end
  rescue
    _exception -> {:error, :cactus_unavailable}
  catch
    :exit, _reason -> {:error, :cactus_unavailable}
  end

  defp validate_audio(path) do
    with true <- String.downcase(Path.extname(path)) == ".wav",
         {:ok, %{type: :regular, size: size}} when size > 0 and size <= @max_audio_bytes <-
           File.stat(path),
         {:ok, %{duration: duration, streams: streams}} <- MediaAnalysis.probe(path),
         true <- is_number(duration) and duration > 0 and duration <= @max_clip_seconds,
         true <- Enum.any?(streams, &(&1.codec_type == "audio")) do
      :ok
    else
      false ->
        {:error, :invalid_comparison_audio}

      {:ok, %{type: :regular, size: size}} when size > @max_audio_bytes ->
        {:error, :comparison_audio_too_large}

      {:ok, _info} ->
        {:error, :invalid_comparison_audio}

      _other ->
        {:error, :invalid_comparison_audio}
    end
  end

  defp selected_models(installed, model_ids)
       when length(model_ids) >= @min_comparison_models and
              length(model_ids) <= @max_comparison_models do
    selected_ids = Enum.uniq(model_ids)

    selected =
      Enum.filter(installed, fn model ->
        model.key in selected_ids or (model.provider == :speaches and model.id in selected_ids)
      end)

    if length(selected_ids) == length(model_ids) and length(selected) == length(model_ids),
      do: {:ok, Enum.sort_by(selected, & &1.key)},
      else: {:error, :comparison_models_unavailable}
  end

  defp selected_models(_installed, _model_ids), do: {:error, :select_two_to_four_models}

  defp validate_reference(nil), do: :ok

  defp validate_reference(text) when is_binary(text) do
    if String.graphemes(String.trim(text)) |> length() <= @max_reference_graphemes,
      do: :ok,
      else: {:error, :reference_text_too_long}
  end

  defp validate_reference(_text), do: {:error, :invalid_reference_text}

  defp character_error_rate(reference, candidate) when is_binary(reference) do
    reference = normalize_reference(reference)
    candidate = normalize_reference(candidate)
    reference_chars = String.graphemes(reference)
    candidate_chars = String.graphemes(candidate)

    case length(reference_chars) do
      0 -> nil
      reference_size -> levenshtein(reference_chars, candidate_chars) / reference_size * 100
    end
  end

  defp character_error_rate(_reference, _candidate), do: nil

  defp normalize_reference(text) do
    text
    |> String.normalize(:nfkc)
    |> String.downcase()
    |> then(&Regex.replace(~r/[\s\p{P}\p{S}]+/u, &1, ""))
  end

  defp levenshtein(left, right) do
    width = length(right)
    initial = :array.from_list(Enum.to_list(0..width))

    final_row =
      left
      |> Enum.with_index(1)
      |> Enum.reduce(initial, fn {left_char, row_index}, previous ->
        current = :array.set(0, row_index, :array.new(width + 1, default: 0))

        Enum.reduce(if(width == 0, do: [], else: 1..width), current, fn column, row ->
          substitution_cost = if left_char == Enum.at(right, column - 1), do: 0, else: 1

          value =
            min(
              :array.get(column, previous) + 1,
              min(
                :array.get(column - 1, row) + 1,
                :array.get(column - 1, previous) + substitution_cost
              )
            )

          :array.set(column, value, row)
        end)
      end)

    :array.get(width, final_row)
  end

  defp japanese_asr?(%{task: task, languages: languages}),
    do: task == "automatic-speech-recognition" and "ja" in languages

  defp japanese_asr?(_model), do: false

  defp model(%{id: id, languages: languages}, installed?, provider),
    do: model(%{"id" => id, "languages" => languages}, installed?, provider)

  defp model(%{"id" => id} = model, installed?, provider) do
    %{
      id: id,
      key: "#{provider}:#{id}",
      provider: provider,
      languages: Map.get(model, "languages", []) |> Enum.filter(&is_binary/1),
      installed?: installed?,
      japanese_supported?: "ja" in Map.get(model, "languages", []),
      experimental?: false,
      lifecycle_stage: if(installed?, do: :installed, else: :candidate),
      promotion_blockers: [
        :representative_japanese_benchmark_required,
        :repeatable_quality_latency_results_required,
        :human_review_required
      ]
    }
  end

  defp default_model, do: "deepdml/faster-whisper-large-v3-turbo-ct2"

  defp safe_error(:speaches_timeout), do: :speaches_timeout
  defp safe_error(:model_load_failed), do: :model_load_failed
  defp safe_error(:cactus_timeout), do: :cactus_timeout
  defp safe_error(:cactus_unavailable), do: :cactus_unavailable
  defp safe_error(:cactus_model_not_installed), do: :model_not_installed
  defp safe_error(:audio_normalization_failed), do: :audio_normalization_failed
  defp safe_error(:ffmpeg_unavailable), do: :ffmpeg_unavailable
  defp safe_error(:invalid_comparison_audio), do: :invalid_comparison_audio
  defp safe_error(:model_unavailable), do: :model_unavailable
  defp safe_error(:invalid_cactus_response), do: :invalid_model_response
  defp safe_error(_reason), do: :model_unavailable

  defp transcribe(%{provider: :cactus, id: model_id}, audio_path),
    do: cactus_adapter().transcribe(audio_path, model_id)

  defp transcribe(%{provider: :speaches, id: model_id}, audio_path),
    do: adapter().transcribe(audio_path, model_id)

  defp adapter do
    Application.get_env(:koe_frame, :speech_models_adapter, SpeachesAdapter)
  end

  defp cactus_adapter do
    Application.get_env(:koe_frame, :cactus_whistle_adapter, CactusWhistleAdapter)
  end
end
