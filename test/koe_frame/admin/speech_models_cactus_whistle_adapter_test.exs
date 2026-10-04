defmodule Defdo.KoeFrame.Admin.SpeechModelsCactusWhistleAdapterTest do
  use ExUnit.Case, async: false

  alias Defdo.KoeFrame.Admin.SpeechModels.CactusWhistleAdapter

  @config_keys [
    :cactus_whistle_runner,
    :cactus_whistle_downloader,
    :cactus_whistle_model_dir,
    :cactus_whistle_timeout_ms,
    :media_analysis_adapter
  ]

  setup do
    previous = Enum.map(@config_keys, &{&1, Application.fetch_env(:koe_frame, &1)})

    root =
      Path.join(
        System.tmp_dir!(),
        "koe-frame-cactus-whistle-#{System.unique_integer([:positive])}"
      )

    model_dir = Path.join(root, "models")
    File.mkdir_p!(root)

    command_path = Path.join(root, "needle-fixture")

    File.write!(command_path, """
    #!/bin/sh
    if [ "$1" = "download" ]; then
      mkdir -p "$4"
      printf 'fake weights' > "$4/whistle.cact"
      printf 'download complete\\n'
      exit 0
    fi
    printf '%s\\n' '{"audio_text":"hello","audio_language":"en","audio_words":[{"text":"hello","start":0.1,"end":0.6}]}'
    """)

    File.chmod!(command_path, 0o755)
    File.write!(Path.join(root, "clip.wav"), "wav fixture")

    Application.put_env(:koe_frame, :cactus_whistle_runner, command_path)
    Application.put_env(:koe_frame, :cactus_whistle_downloader, command_path)
    Application.put_env(:koe_frame, :cactus_whistle_model_dir, model_dir)
    Application.put_env(:koe_frame, :cactus_whistle_timeout_ms, 5_000)

    Application.put_env(
      :koe_frame,
      :media_analysis_adapter,
      Defdo.KoeFrame.Admin.SpeechModelsCactusMediaFake
    )

    on_exit(fn ->
      Enum.each(previous, fn
        {key, {:ok, value}} -> Application.put_env(:koe_frame, key, value)
        {key, :error} -> Application.delete_env(:koe_frame, key)
      end)

      File.rm_rf!(root)
    end)

    {:ok, root: root, model_dir: model_dir, command_path: command_path}
  end

  test "installs the fixed Whistle artifact and transcribes through the native runner", %{
    root: root,
    model_dir: model_dir
  } do
    assert CactusWhistleAdapter.candidate().installable?
    assert CactusWhistleAdapter.candidate().runtime_configured?
    refute CactusWhistleAdapter.candidate().installed?

    assert :ok = CactusWhistleAdapter.download("cactus/whistle")
    assert File.regular?(Path.join(model_dir, "whistle.cact"))
    assert CactusWhistleAdapter.candidate().installed?

    assert {:ok, result} =
             CactusWhistleAdapter.transcribe(Path.join(root, "clip.wav"), "cactus/whistle")

    assert result.text == "hello"
    assert result.language == "en"
    assert result.words == [%{text: "hello", start_ms: 100, end_ms: 600}]
  end

  test "does not pass application secrets into the native runner or downloader", %{
    root: root,
    model_dir: model_dir,
    command_path: command_path
  } do
    previous = System.get_env("KOE_FRAME_CACTUS_SECRET_FIXTURE")
    System.put_env("KOE_FRAME_CACTUS_SECRET_FIXTURE", "fixture-value")

    on_exit(fn ->
      if is_binary(previous),
        do: System.put_env("KOE_FRAME_CACTUS_SECRET_FIXTURE", previous),
        else: System.delete_env("KOE_FRAME_CACTUS_SECRET_FIXTURE")
    end)

    File.write!(command_path, """
    #!/bin/sh
    if [ -n "$KOE_FRAME_CACTUS_SECRET_FIXTURE" ]; then exit 42; fi
    if [ "$1" = "download" ]; then
      mkdir -p "$4"
      printf 'fake weights' > "$4/whistle.cact"
      exit 0
    fi
    printf '%s\\n' '{"audio_text":"hello","audio_language":"en","audio_words":[]}'
    """)

    File.chmod!(command_path, 0o755)

    assert :ok = CactusWhistleAdapter.download("cactus/whistle")

    assert {:ok, %{text: "hello"}} =
             CactusWhistleAdapter.transcribe(Path.join(root, "clip.wav"), "cactus/whistle")

    assert File.regular?(Path.join(model_dir, "whistle.cact"))
  end

  test "does not accept another Cactus model id", %{root: root} do
    assert {:error, :model_unavailable} =
             CactusWhistleAdapter.transcribe(Path.join(root, "clip.wav"), "cactus/other")

    assert {:error, :model_unavailable} = CactusWhistleAdapter.download("cactus/other")
  end

  test "resolves relative runner paths before changing to the model directory", %{
    root: root,
    model_dir: model_dir,
    command_path: command_path
  } do
    relative_command_path = "./.cactus-needle-#{Ecto.UUID.generate()}"
    absolute_command_path = Path.join(File.cwd!(), relative_command_path)
    File.cp!(command_path, absolute_command_path)
    File.chmod!(absolute_command_path, 0o755)
    File.mkdir_p!(model_dir)
    File.write!(Path.join(model_dir, "whistle.cact"), "fake weights")

    Application.put_env(:koe_frame, :cactus_whistle_runner, relative_command_path)
    on_exit(fn -> File.rm(absolute_command_path) end)

    assert {:ok, %{text: "hello"}} =
             CactusWhistleAdapter.transcribe(Path.join(root, "clip.wav"), "cactus/whistle")
  end

  test "reports an installed model as unavailable before its artifact exists", %{root: root} do
    assert {:error, :cactus_model_not_installed} =
             CactusWhistleAdapter.transcribe(Path.join(root, "clip.wav"), "cactus/whistle")
  end
end

defmodule Defdo.KoeFrame.Admin.SpeechModelsCactusMediaFake do
  @moduledoc false

  alias Defdo.KoeFrame.MediaAnalysis.{MediaInfo, MediaStream}

  def probe(_path) do
    {:ok,
     %MediaInfo{
       duration: 2.0,
       streams: [
         %MediaStream{
           index: 0,
           codec_type: "audio",
           codec_name: "pcm_s16le",
           sample_rate: 16_000,
           channels: 1
         }
       ]
     }}
  end
end
