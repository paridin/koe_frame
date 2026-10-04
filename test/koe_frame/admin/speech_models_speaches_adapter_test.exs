defmodule Defdo.KoeFrame.Admin.SpeechModels.SpeachesAdapterTest do
  use ExUnit.Case, async: false

  alias Defdo.KoeFrame.Admin.SpeechModels.SpeachesAdapter

  @config_keys [:runtime_env, :speaches_base_url, :speaches_admin_timeout_ms, :speaches_test_plug]

  setup do
    Req.Test.verify_on_exit!()

    previous = Enum.map(@config_keys, &{&1, Application.fetch_env(:koe_frame, &1)})

    root =
      Path.join(
        System.tmp_dir!(),
        "koe-frame-admin-speaches-#{System.unique_integer([:positive])}"
      )

    File.mkdir_p!(root)
    wav_path = Path.join(root, "comparison.wav")
    File.write!(wav_path, "synthetic streaming WAV bytes")

    Application.put_env(:koe_frame, :runtime_env, :test)
    Application.put_env(:koe_frame, :speaches_base_url, "http://speaches.test.invalid")
    Application.put_env(:koe_frame, :speaches_admin_timeout_ms, 1_000)
    Application.put_env(:koe_frame, :speaches_test_plug, {Req.Test, __MODULE__})

    on_exit(fn ->
      Enum.each(previous, fn
        {key, {:ok, value}} -> Application.put_env(:koe_frame, key, value)
        {key, :error} -> Application.delete_env(:koe_frame, key)
      end)

      File.rm_rf!(root)
    end)

    {:ok, wav_path: wav_path}
  end

  test "loads and normalizes registry and installed models" do
    Req.Test.expect(__MODULE__, fn conn ->
      assert conn.method == "GET"
      assert conn.request_path == "/v1/registry"
      assert conn.query_string == "task=automatic-speech-recognition"

      Req.Test.json(conn, %{
        "data" => [
          %{
            "id" => "kotoba-tech/kotoba-whisper-v2.0-faster",
            "task" => "automatic-speech-recognition",
            "language" => ["ja", "en"]
          },
          %{"id" => "bad/model/extra", "languages" => ["ja"]}
        ]
      })
    end)

    Req.Test.expect(__MODULE__, fn conn ->
      assert conn.method == "GET"
      assert conn.request_path == "/v1/models"
      Req.Test.json(conn, %{"data" => [%{"id" => "Systran/faster-whisper-small"}]})
    end)

    assert {:ok, [registered]} = SpeachesAdapter.registry()
    assert registered.id == "kotoba-tech/kotoba-whisper-v2.0-faster"
    assert registered.task == "automatic-speech-recognition"
    assert registered.languages == ["ja", "en"]

    assert {:ok, [installed]} = SpeachesAdapter.installed()
    assert installed.id == "Systran/faster-whisper-small"
  end

  test "posts a validated model identifier to Speaches install endpoint" do
    Req.Test.expect(__MODULE__, fn conn ->
      assert conn.method == "POST"
      assert conn.request_path == "/v1/models/kotoba-tech/kotoba-whisper-v2.0-faster"
      Req.Test.json(conn, %{"status" => "downloaded"})
    end)

    assert :ok = SpeachesAdapter.download("kotoba-tech/kotoba-whisper-v2.0-faster")
    assert {:error, :model_unavailable} = SpeachesAdapter.download("../../arbitrary")
    assert {:error, :model_unavailable} = SpeachesAdapter.download("../models")
  end

  test "sends the same WAV as a Japanese transcription request and keeps transcript and words", %{
    wav_path: wav_path
  } do
    Req.Test.expect(__MODULE__, fn conn ->
      assert conn.method == "POST"
      assert conn.request_path == "/v1/audio/transcriptions"
      assert [content_type] = Plug.Conn.get_req_header(conn, "content-type")
      assert content_type =~ "multipart/form-data; boundary="

      conn =
        Plug.Parsers.call(
          conn,
          Plug.Parsers.init(parsers: [:multipart], pass: ["*/*"], json_decoder: Jason)
        )

      assert conn.body_params["model"] == "kotoba-tech/kotoba-whisper-v2.0-faster"
      assert conn.body_params["language"] == "ja"
      assert conn.body_params["timestamp_granularities"] == ["word"]

      assert %Plug.Upload{path: upload_path, filename: "comparison.wav"} =
               conn.body_params["file"]

      assert File.read!(upload_path) == File.read!(wav_path)

      Req.Test.json(conn, %{
        "text" => "こんにちは。",
        "words" => [%{"word" => "こんにちは", "start" => 0.1, "end" => 0.8}]
      })
    end)

    assert {:ok, %{text: "こんにちは。", words: [%{text: "こんにちは", start_ms: 100, end_ms: 800}]}} =
             SpeachesAdapter.transcribe(wav_path, "kotoba-tech/kotoba-whisper-v2.0-faster")
  end

  test "does not expose provider error bodies" do
    Req.Test.expect(__MODULE__, fn conn ->
      conn
      |> Plug.Conn.put_status(503)
      |> Req.Test.json(%{"detail" => "synthetic private backend detail"})
    end)

    assert {:error, :speaches_unavailable} = SpeachesAdapter.registry()
  end

  test "requires a private endpoint shape, bounded timeout, and regular audio file", %{
    wav_path: wav_path
  } do
    Application.put_env(:koe_frame, :speaches_base_url, "http://user:pass@speaches.test.invalid")
    assert {:error, :speaches_endpoint_not_configured} = SpeachesAdapter.registry()

    Application.put_env(:koe_frame, :speaches_base_url, "http://speaches.test.invalid")
    Application.put_env(:koe_frame, :speaches_admin_timeout_ms, "1800001")
    assert {:error, :invalid_speaches_timeout} = SpeachesAdapter.registry()

    Application.put_env(:koe_frame, :speaches_admin_timeout_ms, 1_000)

    assert {:error, :invalid_comparison_audio} =
             SpeachesAdapter.transcribe(
               Path.join(Path.dirname(wav_path), "missing.wav"),
               "org/model"
             )
  end
end
