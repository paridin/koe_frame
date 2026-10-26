defmodule Defdo.KoeFrameWeb.Admin.SpeechModelsLiveTest do
  use Defdo.KoeFrameWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  alias Defdo.KoeFrame.Admin.SessionAuthenticatorFake
  alias Defdo.KoeFrameWeb.Admin.SpeechModelsLive

  @user_token "speech-model-admin-test-key"
  @installed [
    %{
      id: "Systran/faster-whisper-small",
      task: "automatic-speech-recognition",
      languages: ["ja"]
    },
    %{id: "test/faster-whisper-medium", task: "automatic-speech-recognition", languages: ["ja"]}
  ]
  @registry [
    %{
      id: "Systran/faster-whisper-small",
      task: "automatic-speech-recognition",
      languages: ["ja"]
    },
    %{id: "test/faster-whisper-medium", task: "automatic-speech-recognition", languages: ["ja"]},
    %{
      id: "kotoba-tech/kotoba-whisper-v2.0-faster",
      task: "automatic-speech-recognition",
      languages: ["ja"]
    },
    %{id: "test/english-only", task: "automatic-speech-recognition", languages: ["en"]}
  ]

  @config_keys [
    :admin_session_authenticator,
    :admin_session_authenticator_test_result,
    :admin_session_authenticator_test_pid,
    :admin_scope,
    :speech_models_adapter,
    :cactus_whistle_adapter,
    :speech_models_cactus_test_candidate,
    :speech_models_test_registry,
    :speech_models_test_installed,
    :speech_models_test_download,
    :speech_models_test_transcriptions,
    :speech_models_test_pid,
    :media_analysis_adapter,
    :speech_models_test_probe,
    :speaches_model
  ]

  setup do
    previous = Enum.map(@config_keys, &{&1, Application.fetch_env(:koe_frame, &1)})

    Application.put_env(:koe_frame, :admin_session_authenticator, SessionAuthenticatorFake)
    Application.put_env(:koe_frame, :admin_session_authenticator_test_pid, self())
    Application.put_env(:koe_frame, :admin_scope, "koe-frame:admin")

    Application.put_env(
      :koe_frame,
      :admin_session_authenticator_test_result,
      {:ok,
       %{
         id: "user-1",
         email: "admin@example.test",
         name: "KoeFrame Admin",
         scopes: ["openid", "profile", "koe-frame:admin"]
       }}
    )

    Application.put_env(:koe_frame, :speech_models_adapter, Defdo.KoeFrame.Admin.SpeechModelsFake)

    Application.put_env(
      :koe_frame,
      :cactus_whistle_adapter,
      Defdo.KoeFrame.Admin.SpeechModelsCactusFake
    )

    Application.put_env(:koe_frame, :speech_models_test_pid, self())
    Application.put_env(:koe_frame, :speech_models_test_registry, {:ok, @registry})
    Application.put_env(:koe_frame, :speech_models_test_installed, {:ok, @installed})
    Application.put_env(:koe_frame, :media_analysis_adapter, Defdo.KoeFrame.MediaAnalysisFake)
    Application.put_env(:koe_frame, :speaches_model, "Systran/faster-whisper-small")

    on_exit(fn ->
      Enum.each(previous, fn
        {key, {:ok, value}} -> Application.put_env(:koe_frame, key, value)
        {key, :error} -> Application.delete_env(:koe_frame, key)
      end)
    end)

    :ok
  end

  test "requires an authenticated admin session", %{conn: conn} do
    assert conn |> get("/admin/speech-models") |> redirected_to() == "/auth/callback"
  end

  test "shows installed Japanese models and catalog download actions to KoeFrame admins", %{
    conn: conn
  } do
    {:ok, view, _html} = live(admin_conn(conn), "/admin/speech-models")
    html = render_async(view)

    assert html =~ "Speech model lab"
    assert html =~ "koe-frame-admin-shell"
    assert html =~ "Admin navigation"
    assert html =~ "System status"
    assert html =~ "Systran/faster-whisper-small"
    assert html =~ "test/faster-whisper-medium"
    assert html =~ "kotoba-tech/kotoba-whisper-v2.0-faster"
    refute html =~ "test/english-only"
    assert html =~ "Download to Speaches"
    assert html =~ "Current default"
    assert html =~ "default remains"
    assert html =~ "Experimental provider"
    assert html =~ "Cactus Whistle"
    assert html =~ "Japanese is not listed"
    assert html =~ "Promotion is blocked until all criteria pass"
    assert html =~ "A representative Japanese benchmark set has not been evaluated."
    assert html =~ "The current lifecycle is exploration"
    assert html =~ "Runtime unavailable"
  end

  test "speech model messages update a closed model and return effects separately" do
    assert SpeechModelsLive.parse_msg("refresh", %{}) == {:ok, :refresh}
    assert SpeechModelsLive.parse_msg("refresh", nil) == :error
    assert SpeechModelsLive.parse_msg("download", %{"model_id" => ["bad"]}) == :error

    assert SpeechModelsLive.parse_msg("compare", %{"comparison" => %{"model_ids" => [1]}}) ==
             :error

    loading = %SpeechModelsLive.Model{inventory_status: :loading}
    assert SpeechModelsLive.update(:refresh, loading) == {loading, []}

    ready = %SpeechModelsLive.Model{
      inventory_status: :ready,
      inventory: %{
        installed: [%{key: "speaches:ja-model", id: "ja-model", provider: :speaches}],
        experimental_installed: [%{key: "cactus:whistle", id: "whistle", provider: :cactus}],
        candidates: [%{id: "ja-candidate", installed?: false}],
        experimental_candidates: [%{key: "cactus:new", installed?: false, installable?: true}]
      }
    }

    assert {%{inventory_status: :loading}, [:load_inventory]} =
             SpeechModelsLive.update(:refresh, ready)

    assert {%{download: {:running, "ja-candidate"}, feedback: nil}, [{:download, "ja-candidate"}]} =
             SpeechModelsLive.update({:download, "ja-candidate"}, ready)

    assert SpeechModelsLive.update({:download, "unlisted"}, ready) == {ready, []}

    assert SpeechModelsLive.update({:download, "anything"}, %SpeechModelsLive.Model{}) ==
             {%SpeechModelsLive.Model{}, []}

    assert {%{inventory_status: :error}, []} =
             SpeechModelsLive.update({:inventory_loaded, {:ok, %{}}}, ready)

    assert {%{comparison: :running}, [{:consume_clip, ["ja-model", "cactus:whistle"], nil}]} =
             SpeechModelsLive.update(
               {:compare, ["ja-model", "cactus:whistle"], nil},
               ready
             )

    assert SpeechModelsLive.update({:compare, ["ja-model", "ja-model"], nil}, ready) ==
             {%{ready | feedback: {:warning, "Select a clip and two to four installed models."}},
              []}
  end

  test "keeps the experimental provider visible and explains when Speaches is unavailable", %{
    conn: conn
  } do
    Application.put_env(:koe_frame, :speech_models_test_registry, {:error, :provider_down})

    {:ok, view, _html} = live(admin_conn(conn), "/admin/speech-models")
    html = render_async(view)

    assert html =~ "Speaches is unavailable. Its catalog is hidden"
    assert html =~ "Experimental provider"
    assert html =~ "Cactus Whistle"
  end

  test "model installation is only requested for the displayed catalog model", %{conn: conn} do
    {:ok, view, _html} = live(admin_conn(conn), "/admin/speech-models")
    render_async(view)

    view
    |> element(
      "#download-model-#{Base.url_encode64("speaches:kotoba-tech/kotoba-whisper-v2.0-faster", padding: false)}"
    )
    |> render_click()

    assert render_async(view) =~ "The model provider could not install that model"
    assert_received {:speech_download, "kotoba-tech/kotoba-whisper-v2.0-faster"}
  end

  test "compares selected installed models on an uploaded WAV without persisting the clip", %{
    conn: conn
  } do
    Application.put_env(:koe_frame, :speech_models_test_transcriptions, %{
      "Systran/faster-whisper-small" => {:ok, %{text: "こんにちは", words: [%{text: "こんにちは"}]}},
      "test/faster-whisper-medium" => {:ok, %{text: "さようなら", words: []}}
    })

    {:ok, view, _html} = live(admin_conn(conn), "/admin/speech-models")
    render_async(view)

    upload =
      file_input(view, "#speech-model-comparison", :clip, [
        %{name: "sample.wav", content: <<"RIFF", 20::little-32, "WAVE synthetic test audio">>}
      ])

    render_upload(upload, "sample.wav")

    view
    |> element("#speech-model-comparison")
    |> render_submit(%{
      "comparison" => %{
        "model_ids" => ["Systran/faster-whisper-small", "test/faster-whisper-medium"],
        "reference" => "こんにちは"
      }
    })

    html = render_async(view)

    assert html =~ "speech-model-comparison-results"
    assert html =~ "CER 0.0%"
    assert html =~ "CER 100.0%"
    assert_received {:speech_transcribe, clip_path, "Systran/faster-whisper-small"}
    assert Path.basename(clip_path) =~ ~r/^koe-frame-model-compare-.+\.wav$/
    assert_received {:speech_transcribe, ^clip_path, "test/faster-whisper-medium"}
    refute File.exists?(clip_path)
  end

  test "redirects authenticated users without the admin scope", %{conn: conn} do
    Application.put_env(
      :koe_frame,
      :admin_session_authenticator_test_result,
      {:ok, %{id: "member-1", email: "member@example.test", scopes: ["openid", "profile"]}}
    )

    assert {:error, {:redirect, %{to: "/admin/forbidden"}}} =
             live(admin_conn(conn), "/admin/speech-models")
  end

  defp admin_conn(conn) do
    init_test_session(conn, %{
      "user_token" => @user_token,
      "tenant_id" => "tenant-test",
      "tenant_provision_host" => "koe-frame.example.test"
    })
  end
end
