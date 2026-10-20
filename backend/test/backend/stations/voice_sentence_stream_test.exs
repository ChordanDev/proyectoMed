defmodule Backend.Stations.VoiceSentenceStreamTest do
  @moduledoc """
  Issue #271: the real-time voice reply is generated as a stream, verified
  sentence by sentence and handed to the worker one verified sentence at a time.
  """
  use ExUnit.Case, async: false

  import ExUnit.CaptureLog

  alias Backend.Stations
  alias Backend.Stations.Conversation

  # Streams the scripted pieces from `:stream_script`. `:pause` tells the test
  # it is waiting and blocks until the test sends `:resume`, so generation is
  # provably still running. `{:fail, reason}` ends the stream with an error.
  defmodule ScriptedStreamAdapter do
    @behaviour Backend.Stations.StationAI

    @impl true
    def next_reply(_package, _context) do
      test_pid = Application.fetch_env!(:backend, :stream_test_pid)
      send(test_pid, :regeneration_requested)

      case Application.get_env(:backend, :stream_regeneration) do
        text when is_binary(text) -> {:ok, %{text: text, used_facts: []}}
        _ -> {:error, :no_regeneration}
      end
    end

    @impl true
    def stream_reply(_package, _context, on_text) do
      test_pid = Application.fetch_env!(:backend, :stream_test_pid)

      Application.fetch_env!(:backend, :stream_script)
      |> Enum.reduce_while([], fn
        :pause, acc ->
          send(test_pid, {:generation_paused, self()})

          receive do
            :resume -> {:cont, acc}
          after
            5_000 -> {:halt, {:error, :test_timeout}}
          end

        {:fail, reason}, _acc ->
          {:halt, {:error, reason}}

        text, acc ->
          on_text.(text)
          {:cont, [acc | text]}
      end)
      |> case do
        {:error, reason} -> {:error, reason}
        text -> {:ok, %{text: IO.iodata_to_binary(text)}}
      end
    end
  end

  # Reports every candidate it sees and refuses any containing `:refuse_marker`.
  defmodule MarkerJevAdapter do
    @behaviour Backend.Stations.JevDecision.Adapter

    @impl true
    def decide_patient(%{candidate_text: candidate}) do
      send(Application.fetch_env!(:backend, :stream_test_pid), {:jev_candidate, candidate})
      marker = Application.get_env(:backend, :refuse_marker)

      if is_binary(marker) and String.contains?(candidate, marker),
        do: {:ok, %{status: :semantic_refusal}},
        else: {:ok, %{status: :verified}}
    end

    @impl true
    def decide_rubric(_request), do: {:error, :not_implemented}
  end

  @question "Quando a dor começou?"

  setup do
    keys = [
      :station_ai_adapter,
      :jev_decision_adapter,
      :stream_test_pid,
      :stream_script,
      :stream_regeneration,
      :refuse_marker
    ]

    previous = Map.new(keys, &{&1, Application.get_env(:backend, &1)})

    on_exit(fn ->
      for {key, value} <- previous do
        if value,
          do: Application.put_env(:backend, key, value),
          else: Application.delete_env(:backend, key)
      end
    end)

    Application.put_env(:backend, :station_ai_adapter, ScriptedStreamAdapter)
    Application.put_env(:backend, :jev_decision_adapter, MarkerJevAdapter)
    Application.put_env(:backend, :stream_test_pid, self())
    Application.delete_env(:backend, :refuse_marker)
    Application.delete_env(:backend, :stream_regeneration)

    session = Stations.create_session(%{audio_consent: true})
    %{session_id: session.session_id}
  end

  defp script(pieces), do: Application.put_env(:backend, :stream_script, pieces)

  # Runs the turn in its own process with a sink that reports each handed-over
  # sentence to the test, as the worker channel would.
  defp start_turn(session_id, turn_id \\ 1) do
    test_pid = self()

    Task.async(fn ->
      Stations.stream_voice_turn(session_id, turn_id, @question, [], fn event, acc ->
        send(test_pid, {:to_worker, event})
        {:cont, [event | acc]}
      end)
    end)
  end

  defp run_turn(session_id) do
    session_id |> start_turn() |> Task.await()
  end

  defp patient_texts(session_id) do
    {:ok, session} = Stations.get_session(session_id)
    for %{role: :patient, text: text} <- session.messages, do: text
  end

  test "the first verified sentence is handed to the worker before generation ends",
       %{session_id: id} do
    script(["Começou ", "ontem. ", :pause, "Ainda dói."])
    task = start_turn(id)

    assert_receive {:generation_paused, generator}, 1_000

    assert_receive {:to_worker,
                    {:sentence, %{index: 0, text: "Começou ontem.", turn_id: 1, generation_id: 1}}},
                   1_000

    # Generation is still blocked mid-reply, and nothing else was handed over.
    assert Process.alive?(generator)
    refute_received {:to_worker, _}

    send(generator, :resume)

    assert {{:ok, %{reply_text: "Começou ontem. Ainda dói.", turn_id: 1, generation_id: 1}},
            [_, _]} = Task.await(task)

    assert_received {:to_worker, {:sentence, %{index: 1, text: "Ainda dói."}}}
    assert patient_texts(id) == ["Começou ontem. Ainda dói."]
  end

  test "each sentence is verified with the sentences already verified before it",
       %{session_id: id} do
    script(["Começou ontem. ", "Ainda dói. ", "Muito."])
    assert {{:ok, _}, _} = run_turn(id)

    assert_received {:jev_candidate, "Começou ontem."}
    assert_received {:jev_candidate, "Começou ontem. Ainda dói."}
    assert_received {:jev_candidate, "Começou ontem. Ainda dói. Muito."}
  end

  test "a refused second sentence: the first is spoken and stored, nothing after it is",
       %{session_id: id} do
    Application.put_env(:backend, :refuse_marker, "omeprazol")
    script(["Começou ontem. ", "Tomei omeprazol. ", "Ainda dói."])

    assert {{:ok, %{reply_text: "Começou ontem.", turn_id: 1}}, [_]} = run_turn(id)

    assert_received {:to_worker, {:sentence, %{index: 0, text: "Começou ontem."}}}
    refute_received {:to_worker, _}
    assert patient_texts(id) == ["Começou ontem."]
    # Something was spoken, so there is no regeneration and no third verification.
    refute_received :regeneration_requested
    refute_received {:jev_candidate, "Começou ontem. Tomei omeprazol. Ainda dói."}
    assert {:ok, nil} = Conversation.active_generation(id)
  end

  test "a refused first sentence is regenerated once, and the verified regeneration is spoken",
       %{session_id: id} do
    Application.put_env(:backend, :refuse_marker, "omeprazol")
    Application.put_env(:backend, :stream_regeneration, "Foi ontem. Ainda dói.")
    script(["Tomei omeprazol. ", "Ainda dói."])

    assert {{:ok, %{reply_text: "Foi ontem. Ainda dói."}}, _} = run_turn(id)

    assert_received :regeneration_requested
    assert_received {:to_worker, {:sentence, %{text: "Foi ontem."}}}
    assert_received {:to_worker, {:sentence, %{text: "Ainda dói."}}}
    assert patient_texts(id) == ["Foi ontem. Ainda dói."]
  end

  test "nothing spoken and the regeneration refused keeps the learner turn", %{session_id: id} do
    Application.put_env(:backend, :refuse_marker, "omeprazol")
    Application.put_env(:backend, :stream_regeneration, "Tomei omeprazol hoje.")
    script(["Tomei omeprazol. ", "Ainda dói."])

    assert {{:ok, {:kept, %{turn_id: 1, generation_id: 1, refusal: :semantic_refusal}}}, []} =
             run_turn(id)

    refute_received {:to_worker, _}
    assert patient_texts(id) == []
    assert {:ok, %{messages: [%{role: :learner}]}} = Stations.get_session(id)

    # The kept turn is settled: a retry is a duplicate.
    assert {{:ok, :duplicate}, []} =
             Stations.stream_voice_turn(id, 1, @question, [], fn _e, acc -> {:cont, acc} end)
  end

  test "no unverified text reaches the worker, the transcript or the logs", %{session_id: id} do
    Application.put_env(:backend, :refuse_marker, "SEGREDO")
    script(["Começou ontem. ", "Tenho um SEGREDO", " guardado. ", "Ainda dói."])
    previous = Logger.level()
    Logger.configure(level: :debug)
    on_exit(fn -> Logger.configure(level: previous) end)

    log =
      capture_log([level: :debug], fn ->
        assert {{:ok, %{reply_text: "Começou ontem."}}, events} = run_turn(id)
        refute inspect(events) =~ "SEGREDO"
      end)

    refute log =~ "SEGREDO"
    refute log =~ "Começou"

    assert log =~
             ~r/voice_sentence index=0 generation_ms=\d+ verification_ms=\d+ outcome=verified/

    assert log =~ ~r/voice_sentence index=1 generation_ms=\d+ verification_ms=\d+ outcome=refused/
    refute Enum.any?(patient_texts(id), &(&1 =~ "SEGREDO"))
  end

  test "stage directions are not spoken but stay in the stored reply", %{session_id: id} do
    script(["*(geme)* Começou ontem. ", "(suspira)"])

    assert {{:ok, %{reply_text: "Começou ontem."}}, [_]} = run_turn(id)
    assert_received {:to_worker, {:sentence, %{text: "Começou ontem."}}}
    refute_received {:to_worker, _}
    assert patient_texts(id) == ["*(geme)* Começou ontem. (suspira)"]
  end

  test "a reply made only of stage directions keeps the learner turn", %{session_id: id} do
    script(["*(suspira e olha para o chão)*"])

    assert {{:ok, {:kept, %{refusal: :unspeakable}}}, []} = run_turn(id)
    assert patient_texts(id) == []
  end

  test "a generation failure after a spoken sentence stores what was spoken",
       %{session_id: id} do
    script(["Começou ontem. ", "Ainda ", {:fail, :timeout}])

    assert {{:ok, %{reply_text: "Começou ontem."}}, [_]} = run_turn(id)
    assert patient_texts(id) == ["Começou ontem."]
  end

  test "a generation failure before anything is spoken fails the turn", %{session_id: id} do
    script(["Começou ", {:fail, :timeout}])

    assert {{:error, :station_ai_unavailable}, []} = run_turn(id)
    assert patient_texts(id) == []
    assert {:ok, %{failed_voice_turn: %{turn_id: 1}}} = Stations.get_session(id)
  end

  test "a turn cancelled mid-reply hands nothing more over and stores nothing",
       %{session_id: id} do
    script(["Começou ontem. ", :pause, "Ainda dói."])
    task = start_turn(id)

    assert_receive {:to_worker, {:sentence, %{index: 0}}}, 1_000
    assert_receive {:generation_paused, generator}, 1_000
    assert {:ok, :cancelled} = Stations.cancel_voice_turn(id, turn_id: 1)
    send(generator, :resume)

    assert {{:error, :stale_generation}, [_]} = Task.await(task)
    refute_received {:to_worker, {:sentence, %{index: 1}}}
    assert patient_texts(id) == []
  end

  test "a sink that halts stops the reply and stores only what it accepted",
       %{session_id: id} do
    script(["Começou ontem. ", "Ainda dói. ", "Muito."])

    assert {{:ok, %{reply_text: "Começou ontem."}}, 1} =
             Stations.stream_voice_turn(id, 1, @question, 0, fn _event, count ->
               if count == 0, do: {:cont, 1}, else: {:halt, count}
             end)

    assert patient_texts(id) == ["Começou ontem."]
  end

  test "an adapter without streaming is streamed as one piece", %{session_id: id} do
    defmodule WholeReplyAdapter do
      @behaviour Backend.Stations.StationAI
      @impl true
      def next_reply(_package, _context), do: {:ok, %{text: "Começou ontem. Ainda dói."}}
    end

    Application.put_env(:backend, :station_ai_adapter, WholeReplyAdapter)

    assert {{:ok, %{reply_text: "Começou ontem. Ainda dói."}}, [_, _]} = run_turn(id)
    assert patient_texts(id) == ["Começou ontem. Ainda dói."]
  end

  test "an invalid transcript is refused before any work", %{session_id: id} do
    assert {{:error, :invalid_transcript}, :acc} =
             Stations.stream_voice_turn(id, 1, "   ", :acc, fn _e, acc -> {:cont, acc} end)
  end
end
