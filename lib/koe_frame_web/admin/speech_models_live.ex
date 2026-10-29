defmodule Defdo.KoeFrameWeb.Admin.SpeechModelsLive do
  @moduledoc false

  use Defdo.KoeFrameWeb, :live_view
  use Defdo.Theme.Components

  on_mount({Defdo.KoeFrameWeb.Hook.RequireAdmin, :ensure})

  alias Defdo.Tenant.Context
  alias Defdo.KoeFrame.Admin.SpeechModels

  @max_upload_bytes 25_000_000
  @download_timeout 1_800_000
  @comparison_timeout 7_500_000
  @empty_inventory %{
    installed: [],
    candidates: [],
    experimental_candidates: [],
    experimental_installed: [],
    default_model: nil,
    speaches_available?: false
  }

  defmodule Model do
    @moduledoc false
    defstruct inventory: %{},
              inventory_status: :loading,
              download: :idle,
              comparison: :idle,
              feedback: nil
  end

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
      |> assign(:model, %Model{inventory: @empty_inventory})

    if connected?(socket), do: {:ok, run_cmds(socket, [:load_inventory])}, else: {:ok, socket}
  end

  @impl true
  def handle_event(name, params, socket) when is_binary(name) and is_map(params) do
    case parse_msg(name, params) do
      {:ok, msg} -> {:noreply, dispatch(msg, socket)}
      :error -> {:noreply, socket}
    end
  end

  def handle_event(name, _params, socket) do
    require Logger
    Logger.debug("ignored speech models event #{inspect(name)}")
    {:noreply, socket}
  end

  @impl true
  def handle_async(:inventory, {:ok, result}, socket) do
    {:noreply, dispatch({:inventory_loaded, result}, socket)}
  end

  def handle_async(:inventory, _result, socket),
    do: {:noreply, dispatch({:inventory_loaded, :error}, socket)}

  def handle_async(:download_model, {:ok, result}, socket) do
    {:noreply, dispatch({:download_finished, result}, socket)}
  end

  def handle_async(:download_model, _result, socket),
    do: {:noreply, dispatch({:download_finished, :error}, socket)}

  def handle_async(:compare_models, {:ok, result}, socket) do
    {:noreply, dispatch({:comparison_finished, result}, socket)}
  end

  def handle_async(:compare_models, _result, socket),
    do: {:noreply, dispatch({:comparison_finished, :error}, socket)}

  def handle_async(name, _result, socket) do
    require Logger
    Logger.debug("ignored speech models async result #{inspect(name)}")
    {:noreply, socket}
  end

  def parse_msg("refresh", params) when is_map(params), do: {:ok, :refresh}
  def parse_msg("validate_compare", params) when is_map(params), do: {:ok, :validate_compare}

  def parse_msg("download", %{"model_id" => model_id})
      when is_binary(model_id) and byte_size(model_id) in 1..300,
      do: {:ok, {:download, model_id}}

  def parse_msg("compare", %{"comparison" => params}) when is_map(params) do
    model_ids = Map.get(params, "model_ids", [])
    reference = Map.get(params, "reference", "")

    if is_list(model_ids) and Enum.all?(model_ids, &is_binary/1) and is_binary(reference) do
      {:ok, {:compare, model_ids, reference |> String.trim() |> empty_to_nil()}}
    else
      :error
    end
  end

  def parse_msg(_name, _params), do: :error

  def update(:refresh, %Model{inventory_status: :loading} = model), do: {model, []}
  def update(:refresh, model), do: {%{model | inventory_status: :loading}, [:load_inventory]}
  def update(:validate_compare, model), do: {model, []}

  def update({:inventory_loaded, {:ok, inventory}}, model) when is_map(inventory) do
    if valid_inventory?(inventory) do
      {%{model | inventory: Map.merge(@empty_inventory, inventory), inventory_status: :ready}, []}
    else
      {%{model | inventory_status: :error}, []}
    end
  end

  def update({:inventory_loaded, _result}, model),
    do: {%{model | inventory_status: :error}, []}

  def update({:download, model_id}, %Model{download: :idle} = model) do
    if installable_model?(model.inventory, model_id) do
      {%{model | download: {:running, model_id}, feedback: nil}, [{:download, model_id}]}
    else
      {model, []}
    end
  end

  def update({:download, _model_id}, model), do: {model, []}

  def update({:download_finished, :ok}, %Model{download: {:running, _model_id}} = model) do
    {%{
       model
       | download: :idle,
         inventory_status: :loading,
         feedback: {:notice, "Model download completed. Checking the installed inventory…"}
     }, [:load_inventory]}
  end

  def update({:download_finished, _result}, %Model{download: {:running, _model_id}} = model) do
    {%{
       model
       | download: :idle,
         inventory_status: :loading,
         feedback:
           {:warning,
            "The model provider could not install that model. Check its runtime configuration and try again."}
     }, [:load_inventory]}
  end

  def update({:download_finished, _result}, model), do: {model, []}

  def update({:compare, _model_ids, _reference}, %Model{comparison: :running} = model),
    do: {model, []}

  def update({:compare, model_ids, reference}, model) do
    if valid_selection?(model.inventory, model_ids) do
      {%{model | comparison: :running, feedback: nil}, [{:consume_clip, model_ids, reference}]}
    else
      {%{model | feedback: {:warning, "Select a clip and two to four installed models."}}, []}
    end
  end

  def update(
        {:clip_ready, {:ok, path}, model_ids, reference},
        %Model{comparison: :running} = model
      ),
      do: {model, [{:compare_models, path, model_ids, reference}]}

  def update({:clip_ready, {:error, message}}, %Model{comparison: :running} = model),
    do: {%{model | comparison: :idle, feedback: {:warning, message}}, []}

  def update({:comparison_finished, {:ok, results}}, %Model{comparison: :running} = model)
      when is_list(results),
      do: {%{model | comparison: {:ready, results}}, []}

  def update({:comparison_finished, {:error, reason}}, %Model{comparison: :running} = model),
    do: {%{model | comparison: {:error, comparison_error(reason)}}, []}

  def update({:comparison_finished, _result}, %Model{comparison: :running} = model) do
    {%{
       model
       | comparison:
           {:error,
            "The comparison could not finish. Check the selected provider runtimes and retry."}
     }, []}
  end

  def update(_message, model), do: {model, []}

  defp dispatch(msg, socket) do
    {model, cmds} = update(msg, socket.assigns.model)
    socket |> assign(:model, model) |> run_cmds(cmds)
  end

  defp run_cmds(socket, []), do: socket

  defp run_cmds(socket, [:load_inventory | rest]) do
    tenant_id = socket.assigns.current_tenant_id

    socket =
      start_async(
        socket,
        :inventory,
        fn -> with_tenant_context(tenant_id, &SpeechModels.inventory/0) end,
        timeout: 30_000
      )

    run_cmds(socket, rest)
  end

  defp run_cmds(socket, [{:download, model_id} | rest]) do
    tenant_id = socket.assigns.current_tenant_id

    socket =
      start_async(
        socket,
        :download_model,
        fn -> with_tenant_context(tenant_id, fn -> SpeechModels.download(model_id) end) end,
        timeout: @download_timeout
      )

    run_cmds(socket, rest)
  end

  defp run_cmds(socket, [{:consume_clip, model_ids, reference} | rest]) do
    result = take_uploaded_clip(socket)
    socket = dispatch({:clip_ready, result, model_ids, reference}, socket)
    run_cmds(socket, rest)
  end

  defp run_cmds(socket, [{:compare_models, path, model_ids, reference} | rest]) do
    tenant_id = socket.assigns.current_tenant_id

    socket =
      start_async(
        socket,
        :compare_models,
        fn ->
          try do
            with_tenant_context(tenant_id, fn ->
              SpeechModels.compare(path, model_ids, reference)
            end)
          after
            File.rm(path)
          end
        end,
        timeout: @comparison_timeout
      )

    run_cmds(socket, rest)
  end

  defp with_tenant_context(tenant_id, fun)
       when is_binary(tenant_id) and tenant_id != "" and is_function(fun, 0),
       do: Context.with_context(tenant_id, fun)

  defp with_tenant_context(_tenant_id, _fun), do: {:error, :missing_tenant_context}

  defp inventory_loading?(%Model{inventory_status: :loading}), do: true
  defp inventory_loading?(%Model{}), do: false
  defp inventory_error?(%Model{inventory_status: :error}), do: true
  defp inventory_error?(%Model{}), do: false

  defp speaches_unavailable?(%Model{
         inventory_status: :ready,
         inventory: %{speaches_available?: false}
       }),
       do: true

  defp speaches_unavailable?(%Model{}), do: false
  defp downloading_model_id(%Model{download: {:running, model_id}}), do: model_id
  defp downloading_model_id(%Model{}), do: nil
  defp comparing?(%Model{comparison: :running}), do: true
  defp comparing?(%Model{}), do: false
  defp comparison_results(%Model{comparison: {:ready, results}}), do: results
  defp comparison_results(%Model{}), do: []
  defp comparison_message(%Model{feedback: {_kind, message}}), do: message
  defp comparison_message(%Model{comparison: {:error, message}}), do: message
  defp comparison_message(%Model{}), do: nil

  defp installable_model?(inventory, model_id) do
    Enum.any?(Map.get(inventory, :candidates, []), fn candidate ->
      is_map(candidate) and Map.get(candidate, :id) == model_id and
        not Map.get(candidate, :installed?, false)
    end) or
      Enum.any?(Map.get(inventory, :experimental_candidates, []), fn candidate ->
        is_map(candidate) and Map.get(candidate, :key) == model_id and
          not Map.get(candidate, :installed?, false) and
          Map.get(candidate, :installable?, false)
      end)
  end

  defp valid_selection?(inventory, model_ids) when is_list(model_ids) do
    available =
      Enum.flat_map(
        Map.get(inventory, :installed, []) ++ Map.get(inventory, :experimental_installed, []),
        fn model ->
          if is_map(model) do
            [Map.get(model, :key)] ++
              if(Map.get(model, :provider) == :speaches, do: [Map.get(model, :id)], else: [])
          else
            []
          end
        end
      )

    length(model_ids) in 2..4 and length(Enum.uniq(model_ids)) == length(model_ids) and
      Enum.all?(model_ids, &(&1 in available))
  end

  defp valid_selection?(_inventory, _model_ids), do: false

  defp valid_inventory?(inventory) do
    lists_valid? =
      Enum.all?(
        [:installed, :candidates, :experimental_candidates, :experimental_installed],
        fn key ->
          case Map.get(inventory, key) do
            items when is_list(items) -> Enum.all?(items, &is_map/1)
            _other -> false
          end
        end
      )

    lists_valid? and is_boolean(Map.get(inventory, :speaches_available?))
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.admin_shell
      flash={@flash}
      page_title="Speech model lab"
      current_page={:speech_models}
    >
      <:actions>
        <button
          id="refresh-speech-models"
          type="button"
          class="btn btn-primary btn-sm"
          phx-click="refresh"
          disabled={inventory_loading?(@model)}
        >
          {if inventory_loading?(@model), do: "Refreshing…", else: "Refresh models"}
        </button>
      </:actions>

      <div class="mx-auto w-full max-w-7xl space-y-10">
        <div
          :if={inventory_loading?(@model)}
          id="speech-models-loading"
          class="flex min-h-28 items-center gap-3 text-sm text-base-content/70"
          role="status"
        >
          <span class="loading loading-spinner loading-sm text-primary" aria-hidden="true"></span>
          Reading installed models and provider catalogs…
        </div>

        <.alert :if={inventory_error?(@model)} variant="error" live={false}>
          <p>
            The speech model inventory could not be read. Check provider runtimes, then refresh this page.
          </p>
        </.alert>

        <.alert :if={speaches_unavailable?(@model)} variant="warning" live={false}>
          <p>
            Speaches is unavailable. Its catalog is hidden; the experimental provider remains available below.
          </p>
        </.alert>

        <div class="grid gap-10 xl:grid-cols-[minmax(0,1fr)_21rem] xl:gap-8">
          <div class="min-w-0 space-y-10">
            <section
              id="installed-speech-models"
              data-slot="model-list"
              aria-labelledby="installed-heading"
            >
              <div class="mb-3 flex flex-wrap items-baseline justify-between gap-x-4 gap-y-2">
                <h2 id="installed-heading" class="text-base font-semibold">Installed models</h2>
                <p class="text-sm text-base-content/65">
                  Default:
                  <code class="font-mono text-base-content">{@model.inventory.default_model ||
                    "not configured"}</code>
                </p>
              </div>

              <div
                :if={@model.inventory.installed == [] and !inventory_loading?(@model)}
                class="border-y border-base-300 py-6 text-sm text-base-content/65"
              >
                No Japanese ASR models installed. Choose one from the catalog below.
              </div>

              <div
                :if={@model.inventory.installed != []}
                class="overflow-x-auto border-y border-base-300"
              >
                <table class="table table-sm">
                  <thead>
                    <tr>
                      <th class="pl-2">Model</th>
                      <th>Language</th>
                      <th class="text-right">Compare</th>
                    </tr>
                  </thead>
                  <tbody>
                    <tr
                      :for={model <- @model.inventory.installed}
                      id={"installed-model-#{dom_id(model.id)}"}
                    >
                      <td class="max-w-0 pl-2">
                        <p class="break-all font-mono text-xs sm:text-sm">{model.id}</p>
                        <p
                          :if={model.id == @model.inventory.default_model}
                          class="mt-1 text-xs text-primary"
                        >
                          Active transcription default
                        </p>
                      </td>
                      <td class="whitespace-nowrap text-sm">Japanese</td>
                      <td class="text-right">
                        <input
                          type="checkbox"
                          class="checkbox checkbox-primary checkbox-sm"
                          aria-label={"Compare #{model.id}"}
                          name="comparison[model_ids][]"
                          value={model.key}
                          form="speech-model-comparison"
                          disabled={comparing?(@model)}
                        />
                      </td>
                    </tr>
                  </tbody>
                </table>
              </div>
            </section>

            <section
              id="speech-model-catalog"
              data-slot="model-catalog"
              aria-labelledby="catalog-heading"
            >
              <div class="mb-3 flex flex-col gap-1 sm:flex-row sm:items-baseline sm:justify-between">
                <h2 id="catalog-heading" class="text-base font-semibold">Speaches catalog</h2>
                <p class="text-sm text-base-content/65">
                  Japanese ASR models available from this provider.
                </p>
              </div>

              <p
                :if={@model.inventory.candidates == [] and !inventory_loading?(@model)}
                class="border-y border-base-300 py-6 text-sm text-base-content/65"
              >
                No Japanese ASR candidates returned by Speaches.
              </p>

              <ul
                :if={@model.inventory.candidates != []}
                class="divide-y divide-base-300 border-y border-base-300"
              >
                <li
                  :for={model <- @model.inventory.candidates}
                  class="flex min-w-0 flex-col gap-3 py-4 sm:flex-row sm:items-center sm:justify-between"
                >
                  <div class="min-w-0">
                    <p class="break-all font-mono text-xs sm:text-sm">{model.id}</p>
                    <p class="mt-1 text-xs text-base-content/60">
                      Languages: {Enum.join(model.languages, ", ")}
                    </p>
                  </div>
                  <div class="flex shrink-0 items-center gap-3">
                    <span :if={model.installed?} class="text-xs text-success">Installed</span>
                    <button
                      :if={!model.installed?}
                      id={"download-model-#{dom_id(model.key)}"}
                      type="button"
                      class="btn btn-outline btn-sm"
                      phx-click="download"
                      phx-value-model_id={model.id}
                      disabled={downloading_model_id(@model) != nil}
                    >
                      {if downloading_model_id(@model) == model.id,
                        do: "Downloading…",
                        else: "Download"}
                    </button>
                  </div>
                </li>
              </ul>
            </section>
          </div>

          <aside
            id="compare-speech-models"
            data-slot="comparison-bench"
            class="min-w-0 border-y border-base-300 bg-base-100 px-4 py-5 xl:sticky xl:top-6 xl:self-start xl:border xl:p-5"
            aria-labelledby="comparison-heading"
          >
            <h2 id="comparison-heading" class="text-base font-semibold">Comparison bench</h2>
            <p class="mt-1 text-sm leading-5 text-base-content/65">
              Select 2–4 installed models, then compare them on the same Japanese clip.
            </p>

            <form
              id="speech-model-comparison"
              phx-submit="compare"
              phx-change="validate_compare"
              class="mt-5 space-y-5"
            >
              <div>
                <label for={@uploads.clip.ref} class="mb-2 block text-sm font-medium">WAV clip</label>
                <.live_file_input
                  upload={@uploads.clip}
                  class="file-input file-input-bordered w-full"
                />
                <p class="mt-2 text-xs text-base-content/60">Up to 25 MB · 30 seconds</p>
                <p :for={entry <- @uploads.clip.entries} class="mt-2 text-xs text-base-content/70">
                  {entry.client_name} · {Float.round(entry.progress / 1, 0)}%
                </p>
                <p :for={error <- upload_errors(@uploads.clip)} class="mt-2 text-sm text-error">
                  {upload_error(error)}
                </p>
              </div>

              <div>
                <label for="comparison-reference" class="mb-2 block text-sm font-medium">
                  Reference transcript <span class="font-normal text-base-content/60">optional</span>
                </label>
                <textarea
                  id="comparison-reference"
                  name="comparison[reference]"
                  maxlength="5000"
                  rows="3"
                  class="textarea textarea-bordered w-full"
                  placeholder="Japanese transcript for CER"
                  disabled={comparing?(@model)}
                ></textarea>
              </div>

              <button
                type="submit"
                class="btn btn-primary w-full"
                disabled={
                  comparing?(@model) or
                    length(@model.inventory.installed ++ @model.inventory.experimental_installed) < 2
                }
              >
                {if comparing?(@model), do: "Comparing…", else: "Run comparison"}
              </button>
            </form>

            <.alert :if={comparison_message(@model)} variant="warning" live={false} class="mt-4">
              <p>{comparison_message(@model)}</p>
            </.alert>
          </aside>
        </div>

        <section
          id="experimental-speech-models"
          data-slot="experimental-models"
          aria-labelledby="experimental-heading"
          class="border-t border-base-300 pt-6"
        >
          <header class="mb-2 flex flex-wrap items-baseline justify-between gap-2">
            <h2 id="experimental-heading" class="text-base font-semibold">Experimental provider</h2>
            <p class="text-sm text-base-content/65">Separate from production transcription.</p>
          </header>
          <p
            :if={@model.inventory.experimental_candidates == []}
            class="py-4 text-sm text-base-content/65"
          >
            No experimental candidates are available.
          </p>
          <ul
            :if={@model.inventory.experimental_candidates != []}
            class="divide-y divide-base-300 border-y border-base-300"
          >
            <li
              :for={model <- @model.inventory.experimental_candidates}
              class="grid gap-4 py-5 md:grid-cols-[minmax(0,1fr)_auto] md:items-start"
            >
              <div class="min-w-0">
                <div class="flex flex-wrap items-baseline gap-x-3 gap-y-1">
                  <h3 class="font-semibold">{model.name}</h3>
                  <span class="text-xs text-warning">Experimental</span>
                  <span :if={model.installed?} class="text-xs text-success">Installed</span>
                </div>
                <p class="mt-1 break-all font-mono text-xs text-base-content/60">{model.id}</p>
                <p class="mt-2 max-w-3xl text-sm leading-5 text-base-content/70">
                  Published languages: {Enum.join(model.languages, ", ")}. Japanese is not listed; use Japanese audio only as a negative control.
                </p>
                <p :if={!model.runtime_configured?} class="mt-2 text-sm text-warning">
                  Cactus runner is not configured in this environment.
                </p>
                <details class="mt-3 max-w-3xl text-sm">
                  <summary class="w-fit cursor-pointer text-base-content/70 hover:text-base-content">
                    Promotion blockers · {lifecycle_stage(model.lifecycle_stage)}
                  </summary>
                  <ul class="mt-2 list-disc space-y-1 pl-5 text-base-content/70">
                    <li :for={blocker <- model.promotion_blockers}>{promotion_blocker(blocker)}</li>
                  </ul>
                </details>
              </div>
              <div class="flex flex-wrap items-center gap-4 md:justify-end">
                <label :if={model.comparison_available?} class="flex items-center gap-2 text-sm">
                  <input
                    type="checkbox"
                    class="checkbox checkbox-primary checkbox-sm"
                    aria-label={"Compare #{model.name}"}
                    name="comparison[model_ids][]"
                    value={model.key}
                    form="speech-model-comparison"
                    disabled={comparing?(@model)}
                  /> Compare
                </label>
                <button
                  :if={!model.installed? and model.installable?}
                  id={"download-model-#{dom_id(model.key)}"}
                  type="button"
                  class="btn btn-outline btn-sm"
                  phx-click="download"
                  phx-value-model_id={model.key}
                  disabled={downloading_model_id(@model) != nil}
                >
                  {if downloading_model_id(@model) == model.key,
                    do: "Downloading…",
                    else: "Install for evaluation"}
                </button>
                <span
                  :if={!model.installed? and !model.installable?}
                  class="text-sm text-base-content/60"
                >
                  Runtime unavailable
                </span>
              </div>
            </li>
          </ul>
        </section>

        <section
          :if={comparison_results(@model) != []}
          id="speech-model-comparison-results"
          data-slot="comparison-results"
          aria-labelledby="comparison-results-heading"
          aria-live="polite"
        >
          <h2 id="comparison-results-heading" class="mb-3 text-base font-semibold">
            Comparison results
          </h2>
          <ul class="divide-y divide-base-300 border-y border-base-300">
            <li
              :for={result <- comparison_results(@model)}
              id={"comparison-result-#{dom_id(result.key)}"}
              class="py-4"
            >
              <div class="flex flex-wrap items-baseline justify-between gap-x-4 gap-y-2">
                <h3 class="break-all font-mono text-sm font-semibold">{result.id}</h3>
                <p class="text-sm text-base-content/70">
                  <span class={if result.status == :ok, do: "text-success", else: "text-error"}>
                    {if result.status == :ok, do: "Complete", else: "Failed"}
                  </span>
                  <span :if={result.status == :ok}> · {result.elapsed_ms} ms · {result.word_count} words</span>
                  <span :if={result.character_error_rate != nil}>
                    · CER {Float.round(result.character_error_rate, 2)}%
                  </span>
                  <span :if={result.language}> · Detected {result.language}</span>
                </p>
              </div>
              <p :if={!result.japanese_supported?} class="mt-2 text-sm text-warning">
                Japanese support is not listed for this model.
              </p>
              <p :if={result.transcript} class="mt-3 whitespace-pre-wrap text-sm leading-6">
                {result.transcript}
              </p>
              <p :if={result.error} class="mt-3 text-sm text-error">
                {comparison_error(result.error)}
              </p>
            </li>
          </ul>
        </section>

        <p class="max-w-4xl border-l-2 border-base-300 pl-3 text-sm leading-5 text-base-content/65">
          Downloads only add files to their provider. A single-clip comparison is exploratory evidence; it does not promote a model or change the transcription default ({@model.inventory.default_model ||
            "configured model"}). Evaluation proceeds from Japanese benchmarks to repeatable quality/latency results and human review.
        </p>
      </div>
    </Layouts.admin_shell>
    """
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
