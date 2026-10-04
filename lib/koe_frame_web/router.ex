defmodule Defdo.KoeFrameWeb.Router do
  use Defdo.KoeFrameWeb, :router

  import Defdo.Tenant.ProvisionWeb, only: [tenant_provision_routes: 2]

  pipeline :browser do
    plug(:accepts, ["html"])
    plug(:fetch_session)
    plug(:fetch_live_flash)
    plug(:put_root_layout, html: {Defdo.KoeFrameWeb.Layouts, :root})
    plug(:protect_from_forgery)
    plug(:put_secure_browser_headers)
  end

  pipeline :api do
    plug(:accepts, ["json"])
  end

  pipeline :oauth do
    plug(:accepts, ["html"])
    plug(Defdo.KoeFrameWeb.Plug.OAuthConfig)

    plug(Defdo.DefdoAuth.Plug.AuthorizeCodeWithPKCE,
      scopes: ~w(openid profile),
      authorize_params: &Defdo.KoeFrameWeb.Plug.OAuthConfig.authorize_params/2
    )
  end

  scope "/", Defdo.KoeFrameWeb do
    pipe_through(:browser)

    tenant_provision_routes("/install", adapter: Defdo.KoeFrame.ProvisionWebAdapter)

    get("/", PageController, :home)
  end

  scope "/", Defdo.KoeFrameWeb do
    pipe_through([:browser, :oauth])

    get("/auth/callback", Plug.OAuthCallback, [])
  end

  scope "/admin", Defdo.KoeFrameWeb.Admin do
    pipe_through(:browser)

    live("/", SystemLive, :index)
    live("/speech-models", SpeechModelsLive, :index)
  end

  scope "/admin", Defdo.KoeFrameWeb do
    pipe_through(:browser)

    get("/forbidden", PageController, :forbidden)
  end

  # Other scopes may use custom stacks.
  # scope "/api", Defdo.KoeFrameWeb do
  #   pipe_through :api
  # end

  # Enable LiveDashboard and Swoosh mailbox preview in development
  if Application.compile_env(:koe_frame, :dev_routes) do
    # If you want to use the LiveDashboard in production, you should put
    # it behind authentication and allow only admins to access it.
    # If your application does not have an admins-only section yet,
    # you can use Plug.BasicAuth to set up some basic authentication
    # as long as you are also using SSL (which you should anyway).
    import Phoenix.LiveDashboard.Router

    scope "/dev" do
      pipe_through(:browser)

      live_dashboard("/dashboard", metrics: Defdo.KoeFrameWeb.Telemetry)
      forward("/mailbox", Plug.Swoosh.MailboxPreview)
    end
  end
end
