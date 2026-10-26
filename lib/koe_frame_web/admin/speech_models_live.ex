defmodule Defdo.KoeFrameWeb.Admin.SpeechModelsLive do
  @moduledoc false

  use Defdo.KoeFrameWeb, :live_view
  use Defdo.Theme.Components

  on_mount({Defdo.KoeFrameWeb.Hook.RequireAdmin, :ensure})

  alias Defdo.KoeFrame.Admin.SpeechModels

  @max_upload_bytes 25_000_000
  @download_timeout 1_800_000
  @comparison_timeout 7_500_000

  @impl true
  def mount(_params, _session, socket) do
    socket =
      socket
      |> allow_upload(:clip,
        accept: ~w(.wav),
        max_entries: 1,
        max_file_size: @max_upload_bytes,
        auto_upload: true
      )
      |> assign(:inventory, %{
        installed: [],
        candidates: [],
        experimental_candidates: [],
        experimental_installed: [],
        default_model: nil
      })
      |> assign(:inventory_loading?, true)
      |> assign(:inventory_error?, false)
      |> assign(:speaches_unavailable?, false)
      |> assign(:downloading_model_id, nil)
      |> assign(:comparing?, false)
      |> assign(:comparison_results, [])
      |> assign(:comparison_status, nil)

    if connected?(socket), do: {:ok, start_inventory(socket)}, else: {:ok, socket}
  end

  @impl true
  def handle_event("refresh", _params, socket), do: {:noreply, start_inventory(socket)}

  def handle_event("download", %{"model_id" => model_id}, socket) do
    if socket.assigns.downloading_model_id do
      {:noreply, socket}
    else
      {:noreply,
       socket
       |> assign(:downloading_model_id, model_id)
       |> assign(:comparison_status, nil)
       |> start_async(:download_model, fn -> SpeechModels.download(model_id) end,
         timeout: @download_timeout
       )}
    end
  end

  def handle_event("validate_compare", _params, socket), do: {:noreply, socket}

  def handle_event("compare", %{"comparison" => params}, socket) do
    model_ids = Map.get(params, "model_ids", [])
    reference = params |> Map.get("reference", "") |> String.trim() |> empty_to_nil()

    case take_uploaded_clip(socket) do
      {:ok, path} ->
        socket =
          socket
          |> assign(:comparing?, true)
          |> assign(:comparison_results, [])
          |> assign(:comparison_status, nil)
          |> start_async(
            :compare_models,
            fn ->
              try do
                SpeechModels.compare(path, model_ids, reference)
              after
                File.rm(path)
              end
            end,
            timeout: @comparison_timeout
          )

        {:noreply, socket}

      {:error, message} ->
        {:noreply, assign(socket, :comparison_status, message)}
    end
  end

  def handle_event("compare", _params, socket),
    do: {:noreply, assign(socket, :comparison_status, "Select a clip and two to four models.")}

  @impl true
  def handle_async(:inventory, {:ok, {:ok, inventory}}, socket) do
    {:noreply,
     socket
     |> assign(:inventory, inventory)
     |> assign(:inventory_loading?, false)
     |> assign(:inventory_error?, false)
     |> assign(:speaches_unavailable?, not inventory.speaches_available?)}
  end

  def handle_async(:inventory, _result, socket) do
    {:noreply,
     socket
     |> assign(:inventory_loading?, false)
     |> assign(:inventory_error?, true)
     |> assign(:speaches_unavailable?, false)}
  end

  def handle_async(:download_model, {:ok, :ok}, socket) do
    {:noreply,
     socket
     |> assign(:downloading_model_id, nil)
     |> assign(:comparison_status, "Model download completed. Checking the installed inventory…")
     |> start_inventory()}
  end

  def handle_async(:download_model, _result, socket) do
    {:noreply,
     socket
     |> assign(:downloading_model_id, nil)
     |> assign(
       :comparison_status,
       "The model provider could not install that model. Check its runtime configuration and try again."
     )
     |> start_inventory()}
  end

  def handle_async(:compare_models, {:ok, {:ok, results}}, socket) do
    {:noreply,
     socket
     |> assign(:comparing?, false)
     |> assign(:comparison_results, results)
     |> assign(:comparison_status, nil)}
  end

  def handle_async(:compare_models, {:ok, {:error, reason}}, socket) do
    {:noreply,
     socket
     |> assign(:comparing?, false)
     |> assign(:comparison_status, comparison_error(reason))}
  end

  def handle_async(:compare_models, _result, socket) do
    {:noreply,
     socket
     |> assign(:comparing?, false)
     |> assign(
       :comparison_status,
       "The comparison could not finish. Check the selected provider runtimes and retry."
     )}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <main class="min-h-screen bg-base-200 text-base-content">
      <.page_header
        title="Speech model lab"
        subtitle="Review Japanese speech models available to this KoeFrame instance."
        container={false}
        surface="bg-base-100"
        class="border-b border-base-300"
      >
        <:meta>
          <span>KoeFrame</span>
          <span aria-hidden="true">/</span>
          <span>Admin</span>
        </:meta>
        <:actions>
          <.link navigate="/admin" class="btn btn-ghost btn-sm">System status</.link>
          <button
            id="refresh-speech-models"
            type="button"
            class="btn btn-primary btn-sm"
            phx-click="refresh"
            disabled={@inventory_loading?}
          >
            {if @inventory_loading?, do: "Refreshing…", else: "Refresh models"}
          </button>
        </:actions>
      </.page_header>

      <div class="mx-auto max-w-6xl space-y-8 px-4 py-8 sm:px-6 lg:px-8">
        <div
          :if={@inventory_loading?}
          id="speech-models-loading"
          class="text-sm text-base-content/70"
          role="status"
        >
          Reading installed models and provider catalogs…
        </div>

        <.alert :if={@inventory_error?} variant="error" live={false}>
          <p>
            The speech model inventory could not be read. Check provider runtimes, then refresh this page.
          </p>
        </.alert>

        <.alert :if={@speaches_unavailable?} variant="warning" live={false}>
          <p>
            Speaches is unavailable. Its catalog is hidden; the experimental provider remains available below.
          </p>
        </.alert>

        <.panel id="installed-speech-models" scroll={false} padding="p-5">
          <:header>
            <div class="flex flex-wrap items-center justify-between gap-3">
              <div>
                <h2 class="text-lg font-semibold">Installed Japanese ASR models</h2>
                <p class="mt-1 text-sm text-base-content/65">
                  The current transcription default is <code class="font-mono">{@inventory.default_model || "not configured"}</code>.
                </p>
              </div>
              <.badge variant="neutral" label={"#{length(@inventory.installed)} installed"} />
            </div>
          </:header>

          <div
            :if={@inventory.installed == [] and !@inventory_loading?}
            class="py-5 text-sm text-base-content/65"
          >
            No Japanese ASR models are installed yet. Choose a catalog model below.
          </div>

          <div :if={@inventory.installed != []} class="overflow-x-auto">
            <table class="table table-sm">
              <thead>
                <tr>
                  <th>Model</th><th>Language</th><th>Use in comparison</th>
                </tr>
              </thead>
              <tbody>
                <tr :for={model <- @inventory.installed} id={"installed-model-#{dom_id(model.id)}"}>
                  <td class="font-mono text-sm">{model.id}</td>
                  <td>Japanese</td>
                  <td>
                    <label class="flex items-center gap-2">
                      <input
                        type="checkbox"
                        class="checkbox checkbox-primary checkbox-sm"
                        name="comparison[model_ids][]"
                        value={model.key}
                        form="speech-model-comparison"
                        disabled={@comparing?}
                      />
                      <span
                        :if={model.id == @inventory.default_model}
                        class="text-xs text-base-content/60"
                      >Current default</span>
                    </label>
                  </td>
                </tr>
              </tbody>
            </table>
          </div>
        </.panel>

        <.panel id="speech-model-catalog" scroll={false} padding="p-5">
          <:header>
            <div>
              <h2 class="text-lg font-semibold">Speaches catalog</h2>
              <p class="mt-1 text-sm text-base-content/65">
                Only Japanese speech recognition models listed by the connected Speaches service appear here.
              </p>
            </div>
          </:header>

          <div
            :if={@inventory.candidates == [] and !@inventory_loading?}
            class="py-5 text-sm text-base-content/65"
          >
            No Japanese ASR candidates were returned by Speaches.
          </div>

          <ul class="divide-y divide-base-300">
            <li
              :for={model <- @inventory.candidates}
              class="flex flex-col gap-3 py-4 sm:flex-row sm:items-center sm:justify-between"
            >
              <div class="min-w-0">
                <p class="break-all font-mono text-sm">{model.id}</p>
                <p class="mt-1 text-xs text-base-content/60">
                  Languages: {Enum.join(model.languages, ", ")}
                </p>
              </div>
              <div class="flex items-center gap-3">
                <.badge :if={model.installed?} variant="success" label="Installed" />
                <button
                  :if={!model.installed?}
                  id={"download-model-#{dom_id(model.key)}"}
                  type="button"
                  class="btn btn-outline btn-sm"
                  phx-click="download"
                  phx-value-model_id={model.id}
                  disabled={@downloading_model_id != nil}
                >
                  {if @downloading_model_id == model.id,
                    do: "Downloading…",
                    else: "Download to Speaches"}
                </button>
              </div>
            </li>
          </ul>
        </.panel>

        <.panel id="experimental-speech-models" scroll={false} padding="p-5">
          <:header>
            <div>
              <h2 class="text-lg font-semibold">Experimental provider</h2>
              <p class="mt-1 text-sm text-base-content/65">
                These models run through their own provider adapter and stay outside the Japanese production path.
              </p>
            </div>
          </:header>

          <ul class="divide-y divide-base-300">
            <li
              :for={model <- @inventory.experimental_candidates}
              class="flex flex-col gap-3 py-4 sm:flex-row sm:items-center sm:justify-between"
            >
              <div class="min-w-0">
                <div class="flex flex-wrap items-center gap-2">
                  <p class="font-semibold">{model.name}</p>
                  <.badge variant="warning" label="Experimental" />
                  <.badge :if={model.installed?} variant="success" label="Installed" />
                </div>
                <p class="mt-1 break-all font-mono text-xs text-base-content/60">{model.id}</p>
                <p class="mt-2 text-sm text-base-content/70">
                  Published languages: {Enum.join(model.languages, ", ")}. Japanese is not listed; compare it on Japanese audio as a negative control.
                </p>
                <div class="mt-3 rounded-box border border-base-300 bg-base-200/60 p-3 text-sm">
                  <p>
                    Lifecycle stage: <span class="font-medium">{lifecycle_stage(model.lifecycle_stage)}</span>.
                    Promotion is blocked until all criteria pass:
                  </p>
                  <ul class="mt-2 list-disc space-y-1 pl-5 text-base-content/70">
                    <li :for={blocker <- model.promotion_blockers}>{promotion_blocker(blocker)}</li>
                  </ul>
                </div>
                <p :if={!model.runtime_configured?} class="mt-1 text-xs text-warning">
                  Cactus runner is not configured in this KoeFrame environment.
                </p>
              </div>
              <div class="flex shrink-0 items-center gap-3">
                <label :if={model.comparison_available?} class="flex items-center gap-2 text-sm">
                  <input
                    type="checkbox"
                    class="checkbox checkbox-primary checkbox-sm"
                    name="comparison[model_ids][]"
                    value={model.key}
                    form="speech-model-comparison"
                    disabled={@comparing?}
                  /> Compare
                </label>
                <button
                  :if={!model.installed? and model.installable?}
                  id={"download-model-#{dom_id(model.key)}"}
                  type="button"
                  class="btn btn-outline btn-sm"
                  phx-click="download"
                  phx-value-model_id={model.key}
                  disabled={@downloading_model_id != nil}
                >
                  {if @downloading_model_id == model.key,
                    do: "Downloading…",
                    else: "Download to Cactus lab"}
                </button>
                <.badge
                  :if={!model.installed? and !model.installable?}
                  variant="neutral"
                  label="Runtime unavailable"
                />
              </div>
            </li>
          </ul>
        </.panel>

        <.panel id="compare-speech-models" scroll={false} padding="p-5">
          <:header>
            <div>
              <h2 class="text-lg font-semibold">Compare on one clip</h2>
              <p class="mt-1 text-sm text-base-content/65">
                Run two to four installed models against the same Japanese WAV, then inspect transcripts, detected language, elapsed time, and optional character error rate.
              </p>
            </div>
          </:header>

          <form
            id="speech-model-comparison"
            phx-submit="compare"
            phx-change="validate_compare"
            class="space-y-5"
          >
            <div>
              <label for={@uploads.clip.ref} class="label"><span class="label-text font-medium">Audio clip (WAV, up to 25 MB and 30 seconds)</span></label>
              <.live_file_input upload={@uploads.clip} class="file-input file-input-bordered w-full" />
              <p :for={entry <- @uploads.clip.entries} class="mt-2 text-xs text-base-content/60">
                {entry.client_name} · {Float.round(entry.progress / 1, 0)}%
              </p>
              <p :for={error <- upload_errors(@uploads.clip)} class="mt-2 text-sm text-error">
                {upload_error(error)}
              </p>
            </div>

            <div>
              <label for="comparison-reference" class="label"><span class="label-text font-medium">Reference transcript (optional, Japanese)</span></label>
              <textarea
                id="comparison-reference"
                name="comparison[reference]"
                maxlength="5000"
                rows="3"
                class="textarea textarea-bordered w-full"
                placeholder="Paste a trusted transcript to calculate character error rate."
                disabled={@comparing?}
              ></textarea>
            </div>

            <button
              type="submit"
              class="btn btn-primary"
              disabled={
                @comparing? or length(@inventory.installed ++ @inventory.experimental_installed) < 2
              }
            >
              {if @comparing?, do: "Comparing models…", else: "Compare selected models"}
            </button>
          </form>

          <.alert :if={@comparison_status} variant="warning" live={false} class="mt-5">
            <p>{@comparison_status}</p>
          </.alert>

          <div
            :if={@comparison_results != []}
            id="speech-model-comparison-results"
            class="mt-6 space-y-4"
            aria-live="polite"
          >
            <article
              :for={result <- @comparison_results}
              id={"comparison-result-#{dom_id(result.key)}"}
              class="rounded-box border border-base-300 p-4"
            >
              <div class="flex flex-wrap items-center justify-between gap-2">
                <h3 class="break-all font-mono text-sm font-semibold">{result.id}</h3>
                <div class="flex flex-wrap gap-2">
                  <.badge
                    variant={if result.status == :ok, do: "success", else: "error"}
                    label={if result.status == :ok, do: "Complete", else: "Failed"}
                  />
                  <.badge
                    :if={result.status == :ok}
                    variant="neutral"
                    label={"#{result.elapsed_ms} ms · #{result.word_count} words"}
                  />
                  <.badge
                    :if={result.character_error_rate != nil}
                    variant="info"
                    label={"CER #{Float.round(result.character_error_rate, 2)}%"}
                  />
                  <.badge
                    :if={!result.japanese_supported?}
                    variant="warning"
                    label="Japanese support not listed"
                  />
                  <.badge
                    :if={result.language}
                    variant="neutral"
                    label={"Detected #{result.language}"}
                  />
                </div>
              </div>
              <p :if={result.transcript} class="mt-3 whitespace-pre-wrap text-sm leading-6">
                {result.transcript}
              </p>
              <p :if={result.error} class="mt-3 text-sm text-error">
                {comparison_error(result.error)}
              </p>
            </article>
          </div>
        </.panel>

        <.alert variant="info" live={false} class="items-start">
          <p>
            Downloads only add model files to their configured provider. The current lifecycle is exploration → Japanese benchmark → repeatable quality and latency → human review. A single-clip comparison is exploratory evidence. This page does not promote or activate models, and the transcription default remains {@inventory.default_model ||
              "the configured model"}.
          </p>
        </.alert>
      </div>
    </main>
    """
  end

  defp start_inventory(socket) do
    socket
    |> assign(:inventory_loading?, true)
    |> start_async(:inventory, &SpeechModels.inventory/0, timeout: 30_000)
  end

  defp take_uploaded_clip(socket) do
    paths =
      consume_uploaded_entries(socket, :clip, fn %{path: source}, _entry ->
        destination =
          Path.join(System.tmp_dir!(), "koe-frame-model-compare-#{Ecto.UUID.generate()}.wav")

        case File.cp(source, destination) do
          :ok -> {:ok, destination}
          {:error, _reason} -> {:postpone, nil}
        end
      end)

    case paths do
      [path] -> {:ok, path}
      _ -> {:error, "Upload one WAV clip before comparing models."}
    end
  rescue
    _exception -> {:error, "The audio clip could not be prepared. Upload it again."}
  end

  defp empty_to_nil(""), do: nil
  defp empty_to_nil(value), do: value

  defp upload_error(:too_large), do: "The WAV must be 25 MB or smaller."
  defp upload_error(:not_accepted), do: "Upload a WAV audio file."
  defp upload_error(_error), do: "The file could not be uploaded."

  defp lifecycle_stage(:experimental), do: "experimental candidate"
  defp lifecycle_stage(:installed_experimental), do: "installed for experimental evaluation"
  defp lifecycle_stage(:candidate), do: "candidate"
  defp lifecycle_stage(:installed), do: "installed for evaluation"
  defp lifecycle_stage(_stage), do: "unknown"

  defp promotion_blocker(:japanese_not_in_published_languages),
    do: "Japanese is not in the published language list."

  defp promotion_blocker(:representative_japanese_benchmark_required),
    do: "A representative Japanese benchmark set has not been evaluated."

  defp promotion_blocker(:repeatable_quality_latency_results_required),
    do: "Repeatable quality and latency results are missing."

  defp promotion_blocker(:human_review_required), do: "Human review is pending."

  defp promotion_blocker(_blocker), do: "A required evaluation is incomplete."

  defp comparison_error(:select_two_to_four_models), do: "Select two to four installed models."

  defp comparison_error(:comparison_models_unavailable),
    do: "One or more selected models are no longer installed. Refresh the inventory and retry."

  defp comparison_error(:invalid_comparison_audio),
    do: "The clip must be a valid WAV with audio and last no more than 30 seconds."

  defp comparison_error(:comparison_audio_too_large), do: "The WAV must be 25 MB or smaller."

  defp comparison_error(:reference_text_too_long),
    do: "The reference transcript must be 5,000 characters or fewer."

  defp comparison_error(:cactus_timeout), do: "Cactus Whistle did not finish before the timeout."

  defp comparison_error(:cactus_unavailable),
    do: "Cactus Whistle is unavailable. Check its runner and model directory."

  defp comparison_error(:model_not_installed),
    do: "Install the selected model, refresh, and retry."

  defp comparison_error(_reason),
    do: "The comparison could not finish. Check provider health and retry."

  defp dom_id(value), do: Base.url_encode64(value, padding: false)
end
