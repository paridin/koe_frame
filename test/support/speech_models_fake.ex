defmodule Defdo.KoeFrame.Admin.SpeechModelsFake do
  @moduledoc false

  def registry do
    result = Application.get_env(:koe_frame, :speech_models_test_registry, {:ok, []})
    notify({:speech_registry, self()})
    result
  end

  def installed do
    result = Application.get_env(:koe_frame, :speech_models_test_installed, {:ok, []})
    notify({:speech_installed, self()})
    result
  end

  def download(model_id) do
    notify({:speech_download, model_id})

    case Application.get_env(:koe_frame, :speech_models_test_download) do
      fun when is_function(fun, 1) -> fun.(model_id)
      result -> result || :ok
    end
  end

  def transcribe(path, model_id) do
    notify({:speech_transcribe, path, model_id})

    Application.get_env(:koe_frame, :speech_models_test_transcriptions, %{})
    |> Map.get(model_id, {:error, :speaches_unavailable})
  end

  defp notify(message) do
    case Application.get_env(:koe_frame, :speech_models_test_pid) do
      pid when is_pid(pid) -> send(pid, message)
      _ -> :ok
    end
  end
end

defmodule Defdo.KoeFrame.MediaAnalysisFake do
  @moduledoc false

  def probe(_path) do
    Application.get_env(
      :koe_frame,
      :speech_models_test_probe,
      {:ok,
       %Defdo.KoeFrame.MediaAnalysis.MediaInfo{
         duration: 2.0,
         streams: [%Defdo.KoeFrame.MediaAnalysis.MediaStream{codec_type: "audio"}]
       }}
    )
  end
end
