defmodule Mix.Tasks.KoeFrame.TranscriptReview do
  @moduledoc """
  Lists media streams or prints one local transcript-to-subtitle preview.
  """

  use Mix.Task

  alias Defdo.KoeFrame.TranscriptReview
  alias Defdo.Tenant.Context

  @shortdoc "Preview word alignment against one subtitle stream"
  @requirements ["loadpaths", "app.config"]

  @switches [
    file: :string,
    list_streams: :boolean,
    audio_stream: :integer,
    subtitle_stream: :integer,
    source_language: :string,
    start_ms: :integer,
    duration_ms: :integer
  ]

  @usage """
  Usage:
    mix koe_frame.transcript_review --file PATH --list-streams
    mix koe_frame.transcript_review --file PATH --audio-stream INDEX --subtitle-stream INDEX --source-language ja --start-ms N --duration-ms N
  """

  @impl Mix.Task
  def run(args) do
    {options, positional, invalid} = OptionParser.parse(args, strict: @switches)

    cond do
      positional != [] or invalid != [] ->
        Mix.raise(@usage)

      Keyword.get(options, :list_streams, false) ->
        run_inventory(options)

      true ->
        run_preview(options)
    end
  end

  defp run_inventory(options) do
    with {:ok, path} <- required_file(options),
         {:ok, inventory} <- TranscriptReview.stream_inventory(path) do
      Mix.shell().info(Jason.encode!(inventory, pretty: true))
    else
      {:error, reason} -> fail(reason)
    end
  end

  defp run_preview(options) do
    with {:ok, path} <- required_file(options),
         {:ok, request} <- preview_request(options, path),
         {:ok, tenant_id} <- transcript_tenant(),
         :ok <- start_application(),
         result <-
           Context.with_context(tenant_id, fn ->
             TranscriptReview.preview(request)
           end),
         {:ok, report} <- result do
      Mix.shell().info(Jason.encode!(report, pretty: true))
    else
      {:error, reason} -> fail(reason)
    end
  end

  defp start_application do
    Mix.Task.run("app.start")
    :ok
  end

  defp required_file(options) do
    case Keyword.fetch(options, :file) do
      {:ok, path} when is_binary(path) and path != "" -> {:ok, path}
      _ -> {:error, :file_required}
    end
  end

  defp preview_request(options, path) do
    required = [:audio_stream, :subtitle_stream, :source_language, :start_ms, :duration_ms]

    if Enum.all?(required, &Keyword.has_key?(options, &1)) do
      {:ok,
       %{
         path: path,
         audio_stream: options[:audio_stream],
         subtitle_stream: options[:subtitle_stream],
         source_language: options[:source_language],
         start_ms: options[:start_ms],
         duration_ms: options[:duration_ms]
       }}
    else
      {:error, :preview_options_required}
    end
  end

  defp transcript_tenant do
    case Application.get_env(:koe_frame, :transcript_review_tenant_id) do
      tenant_id when is_binary(tenant_id) and tenant_id != "" -> {:ok, tenant_id}
      _ -> {:error, :tenant_not_configured}
    end
  end

  defp fail({:speaches_http_error, status}) when is_integer(status) do
    Mix.raise("transcript review failed: Speaches returned HTTP #{status}")
  end

  defp fail(reason) when is_atom(reason) do
    Mix.raise("transcript review failed: #{Atom.to_string(reason)}")
  end

  defp fail(_reason), do: Mix.raise("transcript review failed: unexpected error")
end
