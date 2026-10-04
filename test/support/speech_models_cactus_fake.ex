defmodule Defdo.KoeFrame.Admin.SpeechModelsCactusFake do
  @moduledoc false

  @candidate %{
    id: "cactus/whistle",
    key: "cactus:whistle",
    name: "Cactus Whistle",
    provider: :cactus,
    task: "automatic-speech-recognition",
    languages: ["en", "de", "fr", "es", "it", "nl", "pl"],
    installed?: false,
    runtime_configured?: false,
    installable?: false,
    comparison_available?: false,
    experimental?: true,
    japanese_supported?: false,
    lifecycle_stage: :experimental,
    promotion_blockers: [
      :japanese_not_in_published_languages,
      :representative_japanese_benchmark_required,
      :repeatable_quality_latency_results_required,
      :human_review_required
    ]
  }

  def candidate do
    Application.get_env(:koe_frame, :speech_models_cactus_test_candidate, @candidate)
  end

  def download(model_id) do
    notify({:cactus_download, model_id})

    case Application.get_env(
           :koe_frame,
           :speech_models_cactus_test_download,
           {:error, :cactus_unavailable}
         ) do
      {:fun, function} when is_function(function, 1) -> function.(model_id)
      result -> result
    end
  end

  def transcribe(audio_path, model_id) do
    notify({:cactus_transcribe, audio_path, model_id})

    Application.get_env(:koe_frame, :speech_models_cactus_test_transcriptions, %{})
    |> Map.get(model_id, {:error, :cactus_unavailable})
  end

  defp notify(message) do
    case Application.get_env(:koe_frame, :speech_models_test_pid) do
      pid when is_pid(pid) -> send(pid, message)
      _other -> :ok
    end
  end
end
