defmodule Defdo.KoeFrame.Application do
  # See https://elixir.hexdocs.pm/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children =
      [
        Defdo.KoeFrameWeb.Telemetry,
        Defdo.KoeFrame.Repo,
        {DNSCluster, query: Application.get_env(:koe_frame, :dns_cluster_query) || :ignore},
        {Phoenix.PubSub, name: Defdo.KoeFrame.PubSub}
      ] ++
        oban_children() ++
        [
          # Start a worker by calling: Defdo.KoeFrame.Worker.start_link(arg)
          # {Defdo.KoeFrame.Worker, arg},
          # Start to serve requests, typically the last entry
          Defdo.KoeFrameWeb.Endpoint
        ]

    # See https://elixir.hexdocs.pm/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: Defdo.KoeFrame.Supervisor]
    Supervisor.start_link(children, opts)
  end

  defp oban_children do
    if Application.get_env(:koe_frame, :start_oban?, false) do
      [{Oban, Application.fetch_env!(:defdo_order, Oban)}]
    else
      []
    end
  end

  # Tell Phoenix to update the endpoint configuration
  # whenever the application is updated.
  @impl true
  def config_change(changed, _new, removed) do
    Defdo.KoeFrameWeb.Endpoint.config_change(changed, removed)
    :ok
  end
end
