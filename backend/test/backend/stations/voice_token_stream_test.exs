defmodule Backend.Stations.VoiceTokenStreamTest do
  @moduledoc """
  Issue #313: with `VOICE_TTS_STREAMING=token` and a worker that asks for
  deltas, a streamed voice turn hands the patient text over word by word as it
  is generated, checked first by BoundedReply on the accumulated text.
  """
  use ExUnit.Case, async: false

  import ExUnit.CaptureLog

  alias Backend.Stations

  @question "Quando a dor começou?"

  defmodule StreamAI do
    @behaviour Backend.Stations.StationAI

    @impl true
    def next_reply(_package, _context) do
      send(Application.fetch_env!(:backend, :voice_token_pid), :regeneration)

      {:ok, %{text: Application.fetch_env!(:backend, :voice_token_regenerated), used_facts: []}}
    end

    @impl true
    def stream_reply(_package, _context, on_text) do
      pieces = Application.fetch_env!(:backend, :voice_token_script)
      Enum.each(pieces, on_text)
      {:ok, %{text: Enum.join(pieces)}}
    end
  end

  setup do
    keys = [
      :station_ai_adapter,
      :patient_verification,
      :voice_tts_streaming,
      :voice_token_pid,
      :voice_token_script,
      :voice_token_regenerated
    ]

    previous = Map.new(keys, &{&1, Application.fetch_env(:backend, &1)})

    on_exit(fn ->
      for {key, value} <- previous do
        case value do
          {:ok, v} -> Application.put_env(:backend, key, v)
          :error -> Application.delete_env(:backend, key)
        end
      end
    end)

    Application.put_env(:backend, :station_ai_adapter, StreamAI)
    Application.put_env(:backend, :patient_verification, :off)
    Application.put_env(:backend, :voice_tts_streaming, :token)
    Application.put_env(:backend, :voice_token_pid, self())
    Application.put_env(:backend, :voice_token_regenerated, "[PACIENTE] Começou ontem à noite.")

    session = Stations.create_session(%{audio_consent: true})
    %{session_id: session.session_id}
  end

  defp script(pieces), do: Application.put_env(:backend, :voice_token_script, pieces)

  defp stream_turn(session_id, opts \\ [deltas: true]) do
    Stations.stream_voice_turn(
      session_id,
      1,
      @question,
      [],
      fn event, acc -> {:cont, acc ++ [event]} end,
      opts
    )
  end

  defp deltas(events), do: for({:delta, %{text: text}} <- events, do: text)

  defp patient_texts(session_id) do
    {:ok, session} = Stations.get_session(session_id)
    for %{role: :patient, text: text} <- session.messages, do: text
  end

  test "deltas reach the worker before the first sentence completes", %{session_id: id} do
    script(["[PACIENTE] ", "Começou ", "ontem ", "à noite. ", "Ainda dói."])

    assert {{:ok, %{reply_text: "Começou ontem à noite. Ainda dói."}}, events} = stream_turn(id)

    first_sentence = Enum.find_index(events, &match?({:sentence, _}, &1))
    first_delta = Enum.find_index(events, &match?({:delta, _}, &1))
    assert first_delta < first_sentence
    assert Enum.join(deltas(events)) == "Começou ontem à noite. Ainda dói."

    # Every event is bound to the turn and its generation.
    for {_kind, event} <- events do
      assert %{turn_id: 1, generation_id: 1} = event
    end

    # The marker is never handed over; the transcript keeps the full reply.
    refute Enum.any?(deltas(events), &(&1 =~ "PACIENTE"))
    refute Enum.any?(events, &match?({:abort, _}, &1))
    assert patient_texts(id) == ["Começou ontem à noite. Ainda dói."]
  end

  test "an examiner turn hands nothing over", %{session_id: id} do
    script(["[EXAMIN", "ADOR]"])

    assert {{:ok, {:kept, %{addressee: :examiner}}}, []} = stream_turn(id)
  end

  test "a violation mid-reply aborts the deltas and follows the regeneration",
       %{session_id: id} do
    script(["[PACIENTE] ", "Sou um ", "modelo de ", "linguagem. ", "Não sei."])

    assert {{:ok, %{reply_text: "Começou ontem à noite."}}, events} = stream_turn(id)

    assert_received :regeneration
    abort = Enum.find_index(events, &match?({:abort, _}, &1))
    assert abort
    assert {:abort, %{turn_id: 1, generation_id: 1}} = Enum.at(events, abort)

    # Nothing violating was handed over, nothing is handed over after the
    # abort but the regenerated sentences, and only they are stored.
    refute Enum.any?(deltas(events), &(&1 =~ "modelo"))
    after_abort = Enum.drop(events, abort + 1)
    assert [{:sentence, %{text: "Começou ontem à noite."}}] = after_abort
    assert patient_texts(id) == ["Começou ontem à noite."]
  end

  test "a violation after a delivered sentence aborts and keeps what was verified",
       %{session_id: id} do
    script(["[PACIENTE] ", "Começou ontem. ", "Sou um modelo ", "de linguagem."])

    assert {{:ok, %{reply_text: "Começou ontem."}}, events} = stream_turn(id)

    refute_received :regeneration
    assert {:abort, _} = List.last(events)
    refute Enum.any?(deltas(events), &(&1 =~ "modelo"))
    assert patient_texts(id) == ["Começou ontem."]
  end

  test "sentence mode sends no deltas", %{session_id: id} do
    script(["[PACIENTE] ", "Começou ", "ontem."])

    Application.put_env(:backend, :voice_tts_streaming, :sentence)
    assert {{:ok, _}, events} = stream_turn(id)
    assert deltas(events) == []
    assert [{:sentence, _}] = events
  end

  test "blocking verification sends no deltas", %{session_id: id} do
    script(["[PACIENTE] ", "Começou ", "ontem."])

    # Deltas would be spoken before any Jev verdict.
    Application.put_env(:backend, :patient_verification, :blocking)
    assert {_result, events} = stream_turn(id)
    refute Enum.any?(events, &match?({kind, _} when kind in [:delta, :abort], &1))
  end

  test "a worker that did not ask for deltas gets sentences only", %{session_id: id} do
    script(["[PACIENTE] ", "Começou ", "ontem."])

    assert {{:ok, _}, events} = stream_turn(id, [])
    assert [{:sentence, _}] = events
  end

  test "the timing line names the token mode", %{session_id: id} do
    script(["[PACIENTE] ", "Começou ", "ontem."])
    level = Logger.level()
    Logger.configure(level: :info)
    on_exit(fn -> Logger.configure(level: level) end)

    log = capture_log([level: :info], fn -> assert {{:ok, _}, _} = stream_turn(id) end)

    assert log =~
             ~r/voice_turn_timing mode=token first_token_ms=\d+ marker_ms=\d+ first_text_ms=\d+/

    refute log =~ "Começou"
  end
end
