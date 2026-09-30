defmodule Defdo.KoeFrame.Subtitler.HTTPAdapterTest do
  use ExUnit.Case, async: false

  alias Defdo.KoeFrame.Subtitler

  @config_keys [
    :runtime_env,
    :subtitler_cue_base_url,
    :subtitler_cue_test_plug,
    :subtitler_credential_provider
  ]

  @token String.duplicate("t", 40)
  @srt "1\n00:00:01,000 --> 00:00:02,000\nHello\n"
  @cues %{
    "cues" => [
      %{"id" => "cue-1", "start_ms" => 1_000, "end_ms" => 2_000, "text" => "Hello"}
    ]
  }

  setup do
    Req.Test.verify_on_exit!()

    previous = Enum.map(@config_keys, &{&1, Application.fetch_env(:koe_frame, &1)})

    Application.put_env(:koe_frame, :runtime_env, :test)
    Application.put_env(:koe_frame, :subtitler_cue_base_url, "https://subtitler.example")
    Application.put_env(:koe_frame, :subtitler_cue_test_plug, {Req.Test, __MODULE__})

    Application.put_env(
      :koe_frame,
      :subtitler_credential_provider,
      __MODULE__.TestCredentialProvider
    )

    on_exit(fn ->
      Enum.each(previous, fn
        {key, {:ok, value}} -> Application.put_env(:koe_frame, key, value)
        {key, :error} -> Application.delete_env(:koe_frame, key)
      end)
    end)

    :ok
  end

  test "posts only SRT content with the bearer token and returns normalized cues" do
    Req.Test.expect(__MODULE__, fn conn ->
      assert conn.method == "POST"
      assert conn.request_path == "/api/cues/parse"
      assert Plug.Conn.get_req_header(conn, "authorization") == ["Bearer " <> @token]

      {:ok, body, _conn} = Plug.Conn.read_body(conn)
      assert Jason.decode!(body) == %{"content" => @srt, "format" => "srt"}

      Req.Test.json(conn, @cues)
    end)

    assert {:ok, [%{id: "cue-1", start_ms: 1_000, end_ms: 2_000, text: "Hello"}]} =
             Subtitler.normalize_srt(@srt)
  end

  test "maps unauthorized responses without exposing the response body" do
    Req.Test.expect(__MODULE__, fn conn ->
      conn
      |> Plug.Conn.put_status(401)
      |> Req.Test.json(%{"detail" => "sensitive service response"})
    end)

    assert {:error, :unauthorized} = Subtitler.normalize_srt(@srt)
  end

  test "accepts only an ordered cue contract with exact fields and valid ranges" do
    Req.Test.expect(__MODULE__, fn conn ->
      Req.Test.json(conn, %{
        "cues" => [%{"id" => "cue-2", "start_ms" => 1, "end_ms" => 2, "text" => "x"}]
      })
    end)

    assert {:error, :invalid_response} = Subtitler.normalize_srt(@srt)
  end

  test "maps known parser errors through a fixed allowlist" do
    Req.Test.expect(__MODULE__, fn conn ->
      conn
      |> Plug.Conn.put_status(400)
      |> Req.Test.json(%{"error" => %{"code" => "malformed_srt", "detail" => @srt}})
    end)

    assert {:error, :malformed_srt} = Subtitler.normalize_srt(@srt)
  end

  test "does not follow redirects from the credentialed endpoint" do
    Req.Test.expect(__MODULE__, fn conn ->
      conn
      |> Plug.Conn.put_resp_header("location", "https://elsewhere.invalid/collect")
      |> Plug.Conn.send_resp(302, "")
    end)

    assert {:error, :service_error} = Subtitler.normalize_srt(@srt)
  end

  test "rejects plaintext endpoints in production before loading a credential" do
    Application.put_env(:koe_frame, :runtime_env, :prod)
    Application.put_env(:koe_frame, :subtitler_cue_base_url, "http://subtitler.internal")

    assert {:error, :insecure_endpoint} = Subtitler.normalize_srt(@srt)
  end

  test "reports a missing credential without making a request" do
    Application.put_env(
      :koe_frame,
      :subtitler_credential_provider,
      __MODULE__.UnavailableCredentialProvider
    )

    assert {:error, :credential_not_configured} = Subtitler.normalize_srt(@srt)
  end

  test "bounds the streamed response body before JSON decoding" do
    large_text = String.duplicate("x", 8 * 1024 * 1024 + 1)

    Req.Test.expect(__MODULE__, fn conn ->
      Req.Test.json(conn, %{
        "cues" => [
          %{"id" => "cue-1", "start_ms" => 0, "end_ms" => 1, "text" => large_text}
        ]
      })
    end)

    assert {:error, :response_too_large} = Subtitler.normalize_srt(@srt)
  end

  defmodule TestCredentialProvider do
    def fetch_token, do: {:ok, String.duplicate("t", 40)}
  end

  defmodule UnavailableCredentialProvider do
    def fetch_token, do: {:error, :credential_not_configured}
  end
end
