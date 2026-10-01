defmodule Defdo.KoeFrame.TranscriptReview.SpeachesAdapterTest do
  use ExUnit.Case, async: false

  alias Defdo.KoeFrame.TranscriptReview.SpeachesAdapter

  @config_keys [
    :runtime_env,
    :speaches_base_url,
    :speaches_model,
    :speaches_timeout_ms,
    :speaches_test_plug
  ]

  setup do
    Req.Test.verify_on_exit!()

    root =
      Path.join(
        System.tmp_dir!(),
        "koe-frame-speaches-test-#{System.unique_integer([:positive])}"
      )

    File.mkdir_p!(root)
    wav_path = Path.join(root, "segment.wav")
    File.write!(wav_path, "synthetic streaming audio")
    previous = Enum.map(@config_keys, &{&1, Application.fetch_env(:koe_frame, &1)})

    Application.put_env(:koe_frame, :runtime_env, :test)
    Application.put_env(:koe_frame, :speaches_base_url, "http://speaches.test.invalid")
    Application.put_env(:koe_frame, :speaches_model, "test/faster-whisper")
    Application.put_env(:koe_frame, :speaches_timeout_ms, 1_000)
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

  test "streams a multipart WAV request and normalizes word timestamps", %{wav_path: wav_path} do
    Req.Test.expect(__MODULE__, fn conn ->
      assert conn.method == "POST"
      assert conn.request_path == "/v1/audio/transcriptions"
      assert [content_type] = Plug.Conn.get_req_header(conn, "content-type")
      assert content_type =~ "multipart/form-data; boundary="
      assert Plug.Conn.get_req_header(conn, "authorization") == []

      conn =
        Plug.Parsers.call(
          conn,
          Plug.Parsers.init(parsers: [:multipart], pass: ["*/*"], json_decoder: Jason)
        )

      assert conn.body_params["model"] == "test/faster-whisper"
      assert conn.body_params["language"] == "ja"
      assert conn.body_params["response_format"] == "verbose_json"
      assert conn.body_params["timestamp_granularities"] == ["word"]
      assert %Plug.Upload{path: uploaded_path, filename: "segment.wav"} = conn.body_params["file"]
      assert File.read!(uploaded_path) == "synthetic streaming audio"

      Req.Test.json(conn, %{
        "words" => [
          %{"word" => " hello", "start" => 0.0005, "end" => 0.0015},
          %{"word" => " point", "start" => 0.01, "end" => 0.01}
        ]
      })
    end)

    assert {:ok,
            [
              %{text: " hello", start_ms: 1, end_ms: 2},
              %{text: " point", start_ms: 10, end_ms: 10}
            ]} = SpeachesAdapter.transcribe(wav_path, "JA", 1_000)
  end

  test "requires a configured private endpoint and bounded timeout" do
    Application.delete_env(:koe_frame, :speaches_base_url)
    assert {:error, :speaches_endpoint_not_configured} = SpeachesAdapter.configuration()

    Application.put_env(:koe_frame, :speaches_base_url, "http://speaches.test.invalid")
    Application.put_env(:koe_frame, :speaches_timeout_ms, 0)
    assert {:error, :invalid_speaches_timeout} = SpeachesAdapter.configuration()

    Application.put_env(:koe_frame, :speaches_timeout_ms, 300_001)
    assert {:error, :invalid_speaches_timeout} = SpeachesAdapter.configuration()
  end

  test "returns an unauthorized error without exposing a response body", %{wav_path: wav_path} do
    Req.Test.expect(__MODULE__, fn conn ->
      conn
      |> Plug.Conn.put_status(401)
      |> Req.Test.json(%{"detail" => "synthetic private service response"})
    end)

    assert {:error, :speaches_unauthorized} = SpeachesAdapter.transcribe(wav_path, "ja", 1_000)
  end

  test "maps unavailable statuses without exposing their response bodies", %{wav_path: wav_path} do
    Req.Test.expect(__MODULE__, fn conn ->
      conn
      |> Plug.Conn.put_status(503)
      |> Req.Test.json(%{"detail" => "synthetic internal response"})
    end)

    assert {:error, {:speaches_http_error, 503}} =
             SpeachesAdapter.transcribe(wav_path, "ja", 1_000)
  end

  test "requires word timestamps and rejects malformed or out-of-clip words", %{
    wav_path: wav_path
  } do
    Req.Test.expect(__MODULE__, fn conn -> Req.Test.json(conn, %{"text" => "no word data"}) end)

    assert {:error, :word_timestamps_missing} =
             SpeachesAdapter.transcribe(wav_path, "ja", 1_000)

    Req.Test.expect(__MODULE__, fn conn -> Req.Test.json(conn, %{"words" => []}) end)
    assert {:error, :word_timestamps_missing} = SpeachesAdapter.transcribe(wav_path, "ja", 1_000)

    Req.Test.expect(__MODULE__, fn conn ->
      Req.Test.json(conn, %{"words" => [%{"word" => "late", "start" => 1.0, "end" => 1.0}]})
    end)

    assert {:error, :word_timestamp_outside_clip} =
             SpeachesAdapter.transcribe(wav_path, "ja", 1_000)

    Req.Test.expect(__MODULE__, fn conn ->
      Req.Test.json(conn, %{"words" => [%{"word" => "reversed", "start" => 0.5, "end" => 0.4}]})
    end)

    assert {:error, :word_timestamp_outside_clip} =
             SpeachesAdapter.transcribe(wav_path, "ja", 1_000)
  end
end
