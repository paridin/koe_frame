defmodule Defdo.KoeFrame.Admin.SpeechModelsTest do
  use ExUnit.Case, async: false

  alias Defdo.KoeFrame.Admin.SpeechModels
  alias Defdo.KoeFrame.MediaAnalysis.{MediaInfo, MediaStream}

  @config_keys [
    :speech_models_adapter,
    :cactus_whistle_adapter,
    :speech_models_cactus_test_candidate,
    :speech_models_cactus_test_download,
    :speech_models_cactus_test_transcriptions,
    :speech_models_test_registry,
    :speech_models_test_installed,
    :speech_models_test_download,
    :speech_models_test_transcriptions,
    :speech_models_test_pid,
    :speech_models_test_probe,
    :media_analysis_adapter,
    :speaches_model
  ]

  @registry [
    %{
      id: "kotoba-tech/kotoba-whisper-v2.0-faster",
      task: "automatic-speech-recognition",
      languages: ["ja"]
    },
    %{
      id: "Systran/faster-whisper-small",
      task: "automatic-speech-recognition",
      languages: ["ja", "en"]
    },
    %{id: "test/english-only", task: "automatic-speech-recognition", languages: ["en"]},
    %{id: "test/japanese-tts", task: "text-to-speech", languages: ["ja"]}
  ]

  setup do
    previous = Enum.map(@config_keys, &{&1, Application.fetch_env(:koe_frame, &1)})

    root =
      Path.join(
        System.tmp_dir!(),
        "koe-frame-speech-models-#{System.unique_integer([:positive])}"
      )

    File.mkdir_p!(root)
    wav_path = Path.join(root, "sample.wav")
    File.write!(wav_path, "synthetic wav bytes")

    Application.put_env(:koe_frame, :speech_models_adapter, Defdo.KoeFrame.Admin.SpeechModelsFake)

    Application.put_env(
      :koe_frame,
      :cactus_whistle_adapter,
      Defdo.KoeFrame.Admin.SpeechModelsCactusFake
    )

    Application.put_env(:koe_frame, :media_analysis_adapter, Defdo.KoeFrame.MediaAnalysisFake)
    Application.put_env(:koe_frame, :speech_models_test_registry, {:ok, @registry})

    Application.put_env(
      :koe_frame,
      :speech_models_test_installed,
      {:ok,
       [
         %{
           id: "Systran/faster-whisper-small",
           task: "automatic-speech-recognition",
           languages: []
         }
       ]}
    )

    Application.put_env(:koe_frame, :speech_models_test_pid, self())
    Application.put_env(:koe_frame, :speaches_model, "Systran/faster-whisper-small")

    on_exit(fn ->
      Enum.each(previous, fn
        {key, {:ok, value}} -> Application.put_env(:koe_frame, key, value)
        {key, :error} -> Application.delete_env(:koe_frame, key)
      end)

      File.rm_rf!(root)
    end)

    {:ok, wav_path: wav_path}
  end

  test "inventory only exposes Japanese ASR models and joins installed ids to registry metadata" do
    assert {:ok, inventory} = SpeechModels.inventory()

    assert Enum.map(inventory.installed, & &1.id) == ["Systran/faster-whisper-small"]

    assert Enum.map(inventory.candidates, & &1.id) == [
             "Systran/faster-whisper-small",
             "kotoba-tech/kotoba-whisper-v2.0-faster"
           ]

    assert Enum.all?(
             inventory.candidates,
             &(&1.installed? == (&1.id == "Systran/faster-whisper-small"))
           )

    assert inventory.default_model == "Systran/faster-whisper-small"

    assert [%{id: "cactus/whistle", experimental?: true, japanese_supported?: false}] =
             inventory.experimental_candidates

    assert inventory.experimental_installed == []
  end

  test "keeps Cactus Whistle experimental when its published languages omit Japanese" do
    assert {:ok, inventory} = SpeechModels.inventory()
    assert [candidate] = inventory.experimental_candidates
    assert candidate.languages == ["en", "de", "fr", "es", "it", "nl", "pl"]
    assert candidate.lifecycle_stage == :experimental
    assert :japanese_not_in_published_languages in candidate.promotion_blockers
    assert :representative_japanese_benchmark_required in candidate.promotion_blockers
    assert :repeatable_quality_latency_results_required in candidate.promotion_blockers
    assert :human_review_required in candidate.promotion_blockers
    assert {:error, :cactus_not_configured} = SpeechModels.download("cactus:whistle")
    refute_received {:cactus_download, _}
  end

  test "keeps the Cactus candidate visible when Speaches inventory is unavailable" do
    Application.put_env(:koe_frame, :speech_models_test_registry, {:error, :provider_down})

    assert {:ok, inventory} = SpeechModels.inventory()
    refute inventory.speaches_available?
    assert inventory.installed == []
    assert inventory.candidates == []
    assert [%{id: "cactus/whistle"}] = inventory.experimental_candidates
  end

  test "downloads the fixed Cactus candidate only when its runtime is configured" do
    candidate = %{
      Defdo.KoeFrame.Admin.SpeechModelsCactusFake.candidate()
      | installable?: true
    }

    Application.put_env(:koe_frame, :speech_models_cactus_test_candidate, candidate)

    Application.put_env(
      :koe_frame,
      :speech_models_cactus_test_download,
      {:fun,
       fn model_id ->
         Application.put_env(:koe_frame, :speech_models_cactus_test_candidate, %{
           candidate
           | installed?: true,
             runtime_configured?: true,
             comparison_available?: true,
             lifecycle_stage: :installed_experimental
         })

         assert model_id == "cactus/whistle"
         :ok
       end}
    )

    assert :ok = SpeechModels.download("cactus:whistle")
    assert_received {:cactus_download, "cactus/whistle"}
  end

  test "refuses a model outside the current Japanese ASR registry" do
    assert {:error, :model_unavailable} = SpeechModels.download("attacker/arbitrary-model")
    refute_received {:speech_download, _model_id}
  end

  test "does not download an already installed model" do
    assert {:error, :model_already_installed} =
             SpeechModels.download("Systran/faster-whisper-small")

    refute_received {:speech_download, _model_id}
  end

  test "downloads only a registry candidate and verifies it appears in installed inventory" do
    Application.put_env(:koe_frame, :speech_models_test_download, fn model_id ->
      Application.put_env(:koe_frame, :speech_models_test_installed, {
        :ok,
        [
          %{
            id: "Systran/faster-whisper-small",
            task: "automatic-speech-recognition",
            languages: []
          },
          %{id: model_id, task: "automatic-speech-recognition", languages: []}
        ]
      })

      :ok
    end)

    assert :ok = SpeechModels.download("kotoba-tech/kotoba-whisper-v2.0-faster")
    assert_received {:speech_download, "kotoba-tech/kotoba-whisper-v2.0-faster"}
  end

  test "reports when Speaches accepted a download request but the model is still absent" do
    assert {:error, :model_not_installed} =
             SpeechModels.download("kotoba-tech/kotoba-whisper-v2.0-faster")
  end

  test "compares selected installed models on the same bounded WAV and computes Japanese CER", %{
    wav_path: wav_path
  } do
    Application.put_env(:koe_frame, :speech_models_test_installed, {
      :ok,
      Enum.map(["Systran/faster-whisper-small", "test/faster-whisper-medium"], fn id ->
        %{id: id, task: "automatic-speech-recognition", languages: ["ja"]}
      end)
    })

    Application.put_env(:koe_frame, :speech_models_test_transcriptions, %{
      "Systran/faster-whisper-small" => {:ok, %{text: "ねこ。", words: [%{text: "ねこ。"}]}},
      "test/faster-whisper-medium" => {:ok, %{text: "ねこで", words: []}}
    })

    assert {:ok, [first, second]} =
             SpeechModels.compare(
               wav_path,
               ["Systran/faster-whisper-small", "test/faster-whisper-medium"],
               "ねこ"
             )

    assert first.transcript == "ねこ。"
    assert first.character_error_rate == 0.0
    assert second.transcript == "ねこで"
    assert_in_delta second.character_error_rate, 50.0, 0.01
    assert first.status == :ok
    assert first.elapsed_ms >= 0
    assert_received {:speech_transcribe, ^wav_path, "Systran/faster-whisper-small"}
    assert_received {:speech_transcribe, ^wav_path, "test/faster-whisper-medium"}
  end

  test "runs Cactus as an exploratory Japanese negative control beside Speaches", %{
    wav_path: wav_path
  } do
    candidate = %{
      Defdo.KoeFrame.Admin.SpeechModelsCactusFake.candidate()
      | installed?: true,
        runtime_configured?: true,
        installable?: true,
        comparison_available?: true,
        lifecycle_stage: :installed_experimental
    }

    Application.put_env(:koe_frame, :speech_models_cactus_test_candidate, candidate)

    Application.put_env(:koe_frame, :speech_models_cactus_test_transcriptions, %{
      "cactus/whistle" => {:ok, %{text: "hello", words: [%{text: "hello"}], language: "en"}}
    })

    Application.put_env(:koe_frame, :speech_models_test_transcriptions, %{
      "Systran/faster-whisper-small" => {:ok, %{text: "こんにちは", words: []}}
    })

    assert {:ok, [cactus, speaches]} =
             SpeechModels.compare(
               wav_path,
               ["cactus:whistle", "speaches:Systran/faster-whisper-small"],
               "こんにちは"
             )

    assert cactus.provider == :cactus
    assert cactus.id == "cactus/whistle"
    assert cactus.language == "en"
    assert cactus.japanese_supported? == false
    assert cactus.lifecycle_stage == :installed_experimental
    assert cactus.character_error_rate == 100.0
    assert speaches.japanese_supported? == true
    assert_received {:cactus_transcribe, ^wav_path, "cactus/whistle"}
  end

  test "returns per-model errors without dropping successful results", %{wav_path: wav_path} do
    Application.put_env(:koe_frame, :speech_models_test_installed, {
      :ok,
      [
        %{
          id: "Systran/faster-whisper-small",
          task: "automatic-speech-recognition",
          languages: ["ja"]
        },
        %{
          id: "test/faster-whisper-medium",
          task: "automatic-speech-recognition",
          languages: ["ja"]
        }
      ]
    })

    Application.put_env(:koe_frame, :speech_models_test_transcriptions, %{
      "Systran/faster-whisper-small" => {:ok, %{text: "こんにちは", words: []}},
      "test/faster-whisper-medium" => {:error, :speaches_timeout}
    })

    assert {:ok, [success, failure]} =
             SpeechModels.compare(wav_path, [
               "Systran/faster-whisper-small",
               "test/faster-whisper-medium"
             ])

    assert success.status == :ok
    assert failure.status == :error
    assert failure.error == :speaches_timeout
  end

  test "rejects duplicates, too few models, and models absent from installed inventory", %{
    wav_path: wav_path
  } do
    ids = ["Systran/faster-whisper-small", "test/faster-whisper-medium"]

    assert {:error, :select_two_to_four_models} = SpeechModels.compare(wav_path, [hd(ids)])

    assert {:error, :comparison_models_unavailable} =
             SpeechModels.compare(wav_path, [hd(ids), hd(ids)])

    assert {:error, :comparison_models_unavailable} = SpeechModels.compare(wav_path, ids)
    refute_received {:speech_transcribe, _, _}
  end

  test "rejects non-WAV files, oversized clips, long durations, and excessive references", %{
    wav_path: wav_path
  } do
    mp3_path = String.replace_suffix(wav_path, ".wav", ".mp3")
    File.write!(mp3_path, "not wav")
    assert {:error, :invalid_comparison_audio} = SpeechModels.compare(mp3_path, [])

    {:ok, stat} = File.stat(wav_path)
    assert :ok = File.touch(wav_path, stat.mtime)
    File.write!(wav_path, :binary.copy("x", 25_000_001))
    assert {:error, :comparison_audio_too_large} = SpeechModels.compare(wav_path, [])
    File.write!(wav_path, "small again")

    Application.put_env(:koe_frame, :speech_models_test_probe, {
      :ok,
      %MediaInfo{duration: 60.1, streams: [%MediaStream{codec_type: "audio"}]}
    })

    assert {:error, :invalid_comparison_audio} = SpeechModels.compare(wav_path, [])

    Application.put_env(:koe_frame, :speech_models_test_probe, {
      :ok,
      %MediaInfo{duration: 1.0, streams: [%MediaStream{codec_type: "audio"}]}
    })

    assert {:error, :reference_text_too_long} =
             SpeechModels.compare(wav_path, [], String.duplicate("あ", 5_001))
  end
end
