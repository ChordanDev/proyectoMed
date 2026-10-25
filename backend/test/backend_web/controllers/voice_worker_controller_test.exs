defmodule BackendWeb.VoiceWorkerControllerTest do
  use BackendWeb.ConnCase, async: false

  alias Backend.Stations

  @secret "test-worker-secret"
  @valid_fact_reply "A dor começou durante uma caminhada."
  @natural_reply "Começou quando eu estava caminhando, doutor, e ainda não passou."

  defmodule TestSuccessAdapter do
    @behaviour Backend.Stations.StationAI
    @impl true
    def next_reply(_package, _context) do
      {:ok, %{text: "A dor começou durante uma caminhada.", used_facts: []}}
    end
  end

  defmodule TestRefusalAdapter do
    @behaviour Backend.Stations.StationAI
    @impl true
    def next_reply(_package, _context) do
      {:ok, %{text: "Não tenho essa informação", used_facts: []}}
    end
  end

  defmodule TestFailureAdapter do
    @behaviour Backend.Stations.StationAI
    @impl true
    def next_reply(_package, _context) do
      send(Application.fetch_env!(:backend, :voice_turn_test_pid), :failed_adapter_called)
      {:error, :service_unavailable}
    end
  end

  defmodule TestNaturalReplyAdapter do
    @behaviour Backend.Stations.StationAI
    @impl true
    def next_reply(_package, _context) do
      {:ok, %{text: "Começou quando eu estava caminhando, doutor, e ainda não passou."}}
    end
  end

  defmodule TestStageDirectionAdapter do
    @behaviour Backend.Stations.StationAI
    @impl true
    def next_reply(_package, _context) do
      {:ok, %{text: "*(aponta para a fossa ilíaca direita)* Dói aqui embaixo, doutor."}}
    end
  end

  defmodule TestSlowBarrierAdapter do
    @behaviour Backend.Stations.StationAI
    @impl true
    def next_reply(_package, context) do
      test_pid = Application.get_env(:backend, :voice_turn_test_pid)
      if test_pid, do: send(test_pid, {:adapter_called, context})

      receive do
        {:resume_adapter, text} -> {:ok, %{text: text}}
      after
        5000 -> {:error, :timeout}
      end
    end
  end

  defmodule TestVerifyingJevAdapter do
    @behaviour Backend.Stations.JevDecision.Adapter

    @impl true
    def decide_patient(_request), do: {:ok, %{status: :verified}}

    @impl true
    def decide_rubric(_request), do: {:error, :not_implemented}
  end

  defmodule TestRefusingJevAdapter do
    @behaviour Backend.Stations.JevDecision.Adapter

    @impl true
    def decide_patient(_request), do: {:ok, %{status: :semantic_refusal}}

    @impl true
    def decide_rubric(_request), do: {:error, :not_implemented}
  end

  setup %{conn: conn} do
    Application.put_env(:backend, :voice_worker_secret, @secret)
    prev_adapter = Application.get_env(:backend, :station_ai_adapter)
    Application.put_env(:backend, :station_ai_adapter, TestSuccessAdapter)
    prev_jev_adapter = Application.get_env(:backend, :jev_decision_adapter)
    Application.put_env(:backend, :jev_decision_adapter, TestVerifyingJevAdapter)

    on_exit(fn ->
      Application.delete_env(:backend, :voice_worker_secret)
      Application.delete_env(:backend, :voice_turn_test_pid)

      if prev_adapter do
        Application.put_env(:backend, :station_ai_adapter, prev_adapter)
      else
        Application.delete_env(:backend, :station_ai_adapter)
      end

      if prev_jev_adapter do
        Application.put_env(:backend, :jev_decision_adapter, prev_jev_adapter)
      else
        Application.delete_env(:backend, :jev_decision_adapter)
      end
    end)

    {:ok, conn: put_req_header(conn, "authorization", "Bearer " <> @secret)}
  end

  defp context_path(id), do: ~p"/api/internal/voice/sessions/#{id}"
  defp transcripts_path(id), do: ~p"/api/internal/voice/sessions/#{id}/transcripts"
  defp cancel_path(id), do: ~p"/api/internal/voice/sessions/#{id}/cancel"

  test "transcript text is filtered from request logs" do
    assert %{"text" => "[FILTERED]"} = Phoenix.Logger.filter_values(%{"text" => "Onde dói?"})
  end

  describe "authentication" do
    test "rejects a missing or wrong bearer token across all endpoints", %{conn: conn} do
      session = Stations.create_session(%{audio_consent: true})
      id = session.session_id

      bad_conn = put_req_header(conn, "authorization", "Bearer nope")

      assert %{"error" => "unauthorized"} = json_response(get(bad_conn, context_path(id)), 401)

      assert %{"error" => "unauthorized"} =
               json_response(post(bad_conn, transcripts_path(id), %{}), 401)

      assert %{"error" => "unauthorized"} =
               json_response(post(bad_conn, cancel_path(id), %{}), 401)

      unauthed = build_conn()
      assert %{"error" => "unauthorized"} = json_response(get(unauthed, context_path(id)), 401)

      assert %{"error" => "unauthorized"} =
               json_response(post(unauthed, transcripts_path(id), %{}), 401)

      assert %{"error" => "unauthorized"} =
               json_response(post(unauthed, cancel_path(id), %{}), 401)
    end

    test "rejects every request when no secret is configured", %{conn: conn} do
      Application.delete_env(:backend, :voice_worker_secret)
      session = Stations.create_session(%{audio_consent: true})

      conn =
        conn
        |> put_req_header("authorization", "Bearer ")
        |> get(context_path(session.session_id))

      assert json_response(conn, 401)
    end
  end

  describe "GET context" do
    test "restart allocation skips cancelled prefixes without claiming committed history", %{
      conn: conn
    } do
      for fence <- [1, 7] do
        session = Stations.create_session(%{audio_consent: true})
        id = session.session_id

        assert json_response(post(conn, cancel_path(id), %{turn_id: fence}), 409)
        body = conn |> get(context_path(id)) |> json_response(200)
        assert body["last_turn_id"] == 0
        assert body["turn_id_floor"] == fence
        assert {:ok, %{messages: []}} = Stations.get_session(id)

        for _attempt <- 1..2 do
          assert json_response(
                   post(conn, transcripts_path(id), %{turn_id: fence, text: "Cancelled question"}),
                   409
                 )
        end

        next_id = body["turn_id_floor"] + 1

        assert %{"status" => "committed", "turn_id" => ^next_id} =
                 conn
                 |> post(transcripts_path(id), %{turn_id: next_id, text: "New question"})
                 |> json_response(201)

        assert %{"status" => "duplicate", "turn_id" => ^next_id} =
                 conn
                 |> post(transcripts_path(id), %{turn_id: next_id, text: "New question"})
                 |> json_response(200)

        updated = conn |> get(context_path(id)) |> json_response(200)
        assert updated["last_turn_id"] == next_id
        assert updated["turn_id_floor"] == next_id
      end
    end

    test "returns pt-BR, station keyterms and last_turn_id for a consented active session",
         %{conn: conn} do
      session = Stations.create_session(%{audio_consent: true})

      body = conn |> get(context_path(session.session_id)) |> json_response(200)

      assert body["session_id"] == session.session_id
      assert body["language"] == "pt-BR"
      assert body["last_turn_id"] == 0
      assert is_list(body["keyterms"]) and body["keyterms"] != []
    end

    test "refuses sessions without audio consent", %{conn: conn} do
      session = Stations.create_session(%{audio_consent: false})

      assert %{"error" => "no_consent"} =
               conn |> get(context_path(session.session_id)) |> json_response(403)
    end

    test "refuses unknown, completed and expired sessions", %{conn: conn} do
      assert json_response(get(conn, context_path("missing")), 404)

      session = Stations.create_session(%{audio_consent: true})
      {:ok, _} = Stations.complete_session(session.session_id)
      assert json_response(get(conn, context_path(session.session_id)), 422)

      # Expired session via conversation_timeout_ms: 0
      prev_timeout = Application.get_env(:backend, :conversation_timeout_ms)
      Application.put_env(:backend, :conversation_timeout_ms, 0)

      try do
        expired = Stations.create_session(%{audio_consent: true})
        assert json_response(get(conn, context_path(expired.session_id)), 410)
      after
        if prev_timeout,
          do: Application.put_env(:backend, :conversation_timeout_ms, prev_timeout),
          else: Application.delete_env(:backend, :conversation_timeout_ms)
      end
    end
  end

  describe "POST transcripts" do
    test "failed final and identical retry both return 503 without a second generation",
         %{conn: conn} do
      Application.put_env(:backend, :station_ai_adapter, TestFailureAdapter)
      Application.put_env(:backend, :voice_turn_test_pid, self())
      session = Stations.create_session(%{audio_consent: true})
      payload = %{turn_id: 1, text: "Onde dói?"}

      first = conn |> post(transcripts_path(session.session_id), payload) |> json_response(503)
      assert first == %{"error" => "station_ai_unavailable"}
      assert_receive :failed_adapter_called

      retry = conn |> post(transcripts_path(session.session_id), payload) |> json_response(503)
      assert retry == first
      refute Map.has_key?(retry, "reply_text")
      refute_receive :failed_adapter_called

      assert {:ok, stored} = Stations.get_session(session.session_id)
      assert [%{role: :learner, modality: :voice, text: "Onde dói?"}] = stored.messages
      assert stored.last_voice_turn_id == 1
      assert stored.active_generation_id == nil
      assert stored.active_voice_turn_id == nil
    end

    test "commits a final transcript, returns verified reply_text, turn_id and generation_id",
         %{conn: conn} do
      session = Stations.create_session(%{audio_consent: true})
      id = session.session_id

      resp =
        conn
        |> post(transcripts_path(id), %{turn_id: 1, text: "Onde dói?"})
        |> json_response(201)

      assert resp["status"] == "committed"
      assert resp["turn_id"] == 1
      assert resp["generation_id"] == 1
      assert resp["reply_text"] == @valid_fact_reply
      # Does not leak used_facts or internal metadata
      refute Map.has_key?(resp, "used_facts")

      {:ok, stored} = Stations.get_session(id)

      assert [
               %{role: :learner, modality: :voice, text: "Onde dói?"},
               %{
                 role: :patient,
                 modality: :voice,
                 text: @valid_fact_reply
               }
             ] = stored.messages

      assert %{"last_turn_id" => 1} = conn |> get(context_path(id)) |> json_response(200)
    end

    test "duplicate finals stay 200 and never replay text", %{conn: conn} do
      session = Stations.create_session(%{audio_consent: true})
      id = session.session_id

      # First turn commits
      assert %{"status" => "committed", "turn_id" => 1} =
               conn
               |> post(transcripts_path(id), %{turn_id: 1, text: "Onde dói?"})
               |> json_response(201)

      # Duplicate turn_id returns 200 without reply_text or generation_id
      dup_resp =
        conn
        |> post(transcripts_path(id), %{turn_id: 1, text: "Onde dói?"})
        |> json_response(200)

      assert dup_resp == %{"status" => "duplicate", "turn_id" => 1}
      refute Map.has_key?(dup_resp, "reply_text")
      refute Map.has_key?(dup_resp, "generation_id")

      # Stored messages must not be duplicated
      {:ok, stored} = Stations.get_session(id)
      assert length(stored.messages) == 2
    end

    test "treats an older turn_id as a duplicate so reordering never appends twice",
         %{conn: conn} do
      session = Stations.create_session(%{audio_consent: true})
      id = session.session_id

      assert json_response(post(conn, transcripts_path(id), %{turn_id: 2, text: "segunda"}), 201)

      dup_resp =
        conn
        |> post(transcripts_path(id), %{turn_id: 1, text: "primeira"})
        |> json_response(200)

      assert dup_resp == %{"status" => "duplicate", "turn_id" => 1}
      refute Map.has_key?(dup_resp, "reply_text")

      {:ok, stored} = Stations.get_session(id)
      assert [%{text: "segunda"}, %{role: :patient}] = stored.messages
    end

    test "returns the canonical refusal the verified reply carries", %{conn: conn} do
      Application.put_env(:backend, :station_ai_adapter, TestRefusalAdapter)
      session = Stations.create_session(%{audio_consent: true})
      id = session.session_id

      resp =
        conn
        |> post(transcripts_path(id), %{turn_id: 1, text: "Qual seu prato preferido?"})
        |> json_response(201)

      assert resp["status"] == "committed"
      assert resp["reply_text"] == "Não tenho essa informação"
    end

    test "returns reply_text without stage directions (#269)", %{conn: conn} do
      Application.put_env(:backend, :station_ai_adapter, TestStageDirectionAdapter)
      session = Stations.create_session(%{audio_consent: true})

      resp =
        conn
        |> post(transcripts_path(session.session_id), %{turn_id: 1, text: "Onde dói?"})
        |> json_response(201)

      assert resp["status"] == "committed"
      assert resp["reply_text"] == "Dói aqui embaixo, doutor."
    end

    test "returns a Jev-approved reply verbatim even when it is not an exact package fact",
         %{conn: conn} do
      Application.put_env(:backend, :station_ai_adapter, TestNaturalReplyAdapter)
      session = Stations.create_session(%{audio_consent: true})
      id = session.session_id

      resp =
        conn
        |> post(transcripts_path(id), %{turn_id: 1, text: "Quando a dor começou?"})
        |> json_response(201)

      assert resp["status"] == "committed"
      assert resp["reply_text"] == @natural_reply

      {:ok, stored} = Stations.get_session(id)
      assert [%{role: :learner}, %{role: :patient, text: @natural_reply}] = stored.messages
    end

    # Issue #269: a refusal keeps the learner turn, as on the text path (#235).
    test "a reply Jev refuses returns 201 kept without text and commits no patient message",
         %{conn: conn} do
      Application.put_env(:backend, :station_ai_adapter, TestNaturalReplyAdapter)
      Application.put_env(:backend, :jev_decision_adapter, TestRefusingJevAdapter)
      session = Stations.create_session(%{audio_consent: true})
      id = session.session_id

      resp =
        conn
        |> post(transcripts_path(id), %{turn_id: 1, text: "Quando a dor começou?"})
        |> json_response(201)

      assert resp == %{
               "turn_id" => 1,
               "status" => "kept",
               "generation_id" => 1,
               "addressee" => "patient"
             }

      {:ok, stored} = Stations.get_session(id)
      assert [%{role: :learner, text: "Quando a dor começou?"}] = stored.messages

      # A retry of the kept turn is a duplicate, never a second generation.
      assert %{"status" => "duplicate"} =
               build_conn()
               |> put_req_header("authorization", "Bearer " <> @secret)
               |> post(transcripts_path(id), %{turn_id: 1, text: "Quando a dor começou?"})
               |> json_response(200)
    end

    test "rejects malformed payloads", %{conn: conn} do
      session = Stations.create_session(%{audio_consent: true})
      id = session.session_id

      for body <- [
            %{turn_id: 0, text: "x"},
            %{turn_id: -1, text: "x"},
            %{turn_id: "1", text: "x"},
            %{turn_id: 1, text: "  "},
            %{turn_id: 1}
          ] do
        assert %{"error" => "invalid_transcript"} =
                 json_response(post(conn, transcripts_path(id), body), 400)
      end
    end

    test "refuses transcripts for sessions without consent or no longer active", %{conn: conn} do
      no_consent = Stations.create_session(%{audio_consent: false})

      assert %{"error" => "no_consent"} =
               json_response(
                 post(conn, transcripts_path(no_consent.session_id), %{turn_id: 1, text: "x"}),
                 403
               )

      done = Stations.create_session(%{audio_consent: true})
      {:ok, _} = Stations.complete_session(done.session_id)

      assert %{"error" => "session_completed"} =
               json_response(
                 post(conn, transcripts_path(done.session_id), %{turn_id: 1, text: "x"}),
                 422
               )

      prev_timeout = Application.get_env(:backend, :conversation_timeout_ms)
      Application.put_env(:backend, :conversation_timeout_ms, 0)

      try do
        expired = Stations.create_session(%{audio_consent: true})

        assert %{"error" => "session_expired"} =
                 json_response(
                   post(conn, transcripts_path(expired.session_id), %{turn_id: 1, text: "x"}),
                   410
                 )
      after
        if prev_timeout,
          do: Application.put_env(:backend, :conversation_timeout_ms, prev_timeout),
          else: Application.delete_env(:backend, :conversation_timeout_ms)
      end

      assert %{"error" => "session_not_found"} =
               json_response(
                 post(conn, transcripts_path("non-existent-id"), %{turn_id: 1, text: "x"}),
                 404
               )
    end
  end

  describe "POST transcripts after the station deadline (#201)" do
    setup do
      original_duration = Application.get_env(:backend, :station_duration_ms)
      original_grace = Application.get_env(:backend, :turn_grace_ms)

      on_exit(fn ->
        restore_env(:station_duration_ms, original_duration)
        restore_env(:turn_grace_ms, original_grace)
      end)

      :ok
    end

    test "a turn on a session completed by the timer returns 409 station_time_elapsed",
         %{conn: conn} do
      Application.put_env(:backend, :station_duration_ms, 30)
      session = Stations.create_session(%{audio_consent: true})
      id = session.session_id

      wait_until(fn -> match?({:ok, %{status: :completed}}, Stations.get_session(id)) end)

      resp =
        conn
        |> post(transcripts_path(id), %{turn_id: 1, text: "Chegou tarde"})
        |> json_response(409)

      assert resp == %{"error" => "station_time_elapsed"}
      assert {:ok, %{messages: [], completion_reason: :timer}} = Stations.get_session(id)
    end

    test "a new turn past the deadline returns 409 while the in-flight turn still replies inside grace",
         _tags do
      Application.put_env(:backend, :station_duration_ms, 300)
      Application.put_env(:backend, :turn_grace_ms, 3_000)
      Application.put_env(:backend, :station_ai_adapter, TestSlowBarrierAdapter)
      Application.put_env(:backend, :voice_turn_test_pid, self())

      session = Stations.create_session(%{audio_consent: true})
      id = session.session_id

      in_flight =
        Task.async(fn ->
          build_conn()
          |> put_req_header("authorization", "Bearer " <> @secret)
          |> post(transcripts_path(id), %{turn_id: 1, text: "Onde dói?"})
        end)

      assert_receive {:adapter_called, _context}, 1000

      # Past the deadline, inside the grace window of the in-flight generation.
      Process.sleep(450)

      late =
        build_conn()
        |> put_req_header("authorization", "Bearer " <> @secret)
        |> post(transcripts_path(id), %{turn_id: 2, text: "Chegou tarde"})
        |> json_response(409)

      assert late == %{"error" => "station_time_elapsed"}

      send(in_flight.pid, {:resume_adapter, @valid_fact_reply})
      resp = in_flight |> Task.await() |> json_response(201)
      assert resp["reply_text"] == @valid_fact_reply

      assert {:ok, %{status: :completed, completion_reason: :timer} = stored} =
               Stations.get_session(id)

      assert [
               %{role: :learner, text: "Onde dói?"},
               %{role: :patient, text: @valid_fact_reply}
             ] = stored.messages
    end

    test "a generation cut off by the deadline returns 409 station_time_elapsed and no text",
         _tags do
      Application.put_env(:backend, :station_duration_ms, 200)
      Application.put_env(:backend, :turn_grace_ms, 100)
      Application.put_env(:backend, :station_ai_adapter, TestSlowBarrierAdapter)
      Application.put_env(:backend, :voice_turn_test_pid, self())

      session = Stations.create_session(%{audio_consent: true})
      id = session.session_id

      task =
        Task.async(fn ->
          build_conn()
          |> put_req_header("authorization", "Bearer " <> @secret)
          |> post(transcripts_path(id), %{turn_id: 1, text: "Onde dói?"})
        end)

      assert_receive {:adapter_called, _context}, 1000

      wait_until(fn -> match?({:ok, %{status: :completed}}, Stations.get_session(id)) end)

      send(task.pid, {:resume_adapter, @valid_fact_reply})

      resp = task |> Task.await() |> json_response(409)
      assert resp == %{"error" => "station_time_elapsed"}
      assert {:ok, %{messages: [], completion_reason: :timer}} = Stations.get_session(id)
    end
  end

  describe "POST cancel" do
    test "cancel before admission fences delayed transcript and retry without appending", %{
      conn: conn
    } do
      session = Stations.create_session(%{audio_consent: true})
      id = session.session_id

      assert %{"error" => "stale_generation"} =
               conn |> post(cancel_path(id), %{turn_id: 1}) |> json_response(409)

      for _attempt <- 1..2 do
        assert %{"error" => "stale_generation"} =
                 conn
                 |> post(transcripts_path(id), %{turn_id: 1, text: "Cancelled question"})
                 |> json_response(409)
      end

      assert {:ok, %{messages: [], last_voice_turn_id: 0}} = Stations.get_session(id)
      assert {:error, :stale_generation} = Stations.commit_voice_transcript(id, 1, "Legacy retry")

      assert {:error, :stale_generation} =
               Stations.process_voice_turn(id, 1, "Public context retry")

      assert %{"status" => "committed", "turn_id" => 2, "generation_id" => 1} =
               conn
               |> post(transcripts_path(id), %{turn_id: 2, text: "Later question"})
               |> json_response(201)

      assert %{"status" => "duplicate", "turn_id" => 2} =
               conn
               |> post(transcripts_path(id), %{turn_id: 2, text: "Later question"})
               |> json_response(200)

      assert {:ok, %{messages: [%{text: "Later question"}, %{role: :patient}]}} =
               Stations.get_session(id)
    end

    test "cancels active generation unconditionally when generation_id is omitted",
         %{conn: conn} do
      session = Stations.create_session(%{audio_consent: true})
      id = session.session_id

      resp =
        conn
        |> post(cancel_path(id), %{})
        |> json_response(200)

      assert resp == %{"status" => "cancelled", "session_id" => id}
    end

    test "returns 409 stale_generation when cancel specifies an inactive generation_id or turn_id",
         %{conn: conn} do
      session = Stations.create_session(%{audio_consent: true})
      id = session.session_id

      resp_gen =
        conn
        |> post(cancel_path(id), %{generation_id: 999})
        |> json_response(409)

      assert resp_gen == %{"error" => "stale_generation"}

      resp_turn =
        conn
        |> post(cancel_path(id), %{turn_id: 999})
        |> json_response(409)

      assert resp_turn == %{"error" => "stale_generation"}
    end

    test "rejects malformed generation_id or turn_id with 400", %{conn: conn} do
      session = Stations.create_session(%{audio_consent: true})
      id = session.session_id

      for bad_id <- [0, -1, "1", %{}, [1]] do
        resp =
          conn
          |> post(cancel_path(id), %{generation_id: bad_id})
          |> json_response(400)

        assert resp == %{"error" => "invalid_generation_id"}
      end

      for bad_id <- [0, -1, "1", %{}, [1]] do
        resp =
          conn
          |> post(cancel_path(id), %{turn_id: bad_id})
          |> json_response(400)

        assert resp == %{"error" => "invalid_turn_id"}
      end
    end

    test "refuses cancel on completed, expired, or missing sessions", %{conn: conn} do
      done = Stations.create_session(%{audio_consent: true})
      {:ok, _} = Stations.complete_session(done.session_id)

      assert %{"error" => "session_completed"} =
               json_response(post(conn, cancel_path(done.session_id), %{}), 422)

      prev_timeout = Application.get_env(:backend, :conversation_timeout_ms)
      Application.put_env(:backend, :conversation_timeout_ms, 0)

      try do
        expired = Stations.create_session(%{audio_consent: true})

        assert %{"error" => "session_expired"} =
                 json_response(post(conn, cancel_path(expired.session_id), %{}), 410)
      after
        if prev_timeout,
          do: Application.put_env(:backend, :conversation_timeout_ms, prev_timeout),
          else: Application.delete_env(:backend, :conversation_timeout_ms)
      end

      assert %{"error" => "session_not_found"} =
               json_response(post(conn, cancel_path("non-existent"), %{}), 404)
    end
  end

  describe "cancellation race and stale generation via controller" do
    test "concurrent turn arriving during generation supersedes previous turn, which returns 409 and no text",
         _tags do
      session = Stations.create_session(%{audio_consent: true})
      id = session.session_id

      Application.put_env(:backend, :station_ai_adapter, TestSlowBarrierAdapter)
      Application.put_env(:backend, :voice_turn_test_pid, self())

      # Worker 1 starts turn 1
      task1 =
        Task.async(fn ->
          build_conn()
          |> put_req_header("authorization", "Bearer " <> @secret)
          |> post(transcripts_path(id), %{turn_id: 1, text: "Primeira pergunta lenta"})
        end)

      assert_receive {:adapter_called, _context}, 1000

      # Worker 2 / learner starts turn 2 while turn 1 generation is pending
      # This supersedes turn 1's generation in Conversation
      conn_turn2 =
        build_conn()
        |> put_req_header("authorization", "Bearer " <> @secret)

      task2 =
        Task.async(fn ->
          post(conn_turn2, transcripts_path(id), %{turn_id: 2, text: "Segunda pergunta"})
        end)

      # Wait for turn 2 to enter adapter
      assert_receive {:adapter_called, _context2}, 1000

      # Now resume turn 1 adapter first
      send(task1.pid, {:resume_adapter, "Resposta descartada 1"})

      # Turn 1 should return 409 stale_generation and NEVER return reply_text
      resp1 = task1 |> Task.await() |> json_response(409)
      assert resp1 == %{"error" => "stale_generation"}
      refute Map.has_key?(resp1, "reply_text")

      # Resume turn 2 adapter with authorized fact
      send(task2.pid, {:resume_adapter, @valid_fact_reply})

      resp2 = task2 |> Task.await() |> json_response(201)
      assert resp2["status"] == "committed"
      assert resp2["turn_id"] == 2
      assert resp2["reply_text"] == @valid_fact_reply

      # Evaluator transcript retains both learner turns but only turn 2's patient reply
      {:ok, stored} = Stations.get_session(id)

      assert [
               %{role: :learner, text: "Primeira pergunta lenta"},
               %{role: :learner, text: "Segunda pergunta"},
               %{role: :patient, text: @valid_fact_reply}
             ] = stored.messages
    end
  end

  defp restore_env(key, nil), do: Application.delete_env(:backend, key)
  defp restore_env(key, value), do: Application.put_env(:backend, key, value)

  describe "POST transcripts as a sentence stream (#271)" do
    defmodule CompletingJevAdapter do
      @behaviour Backend.Stations.JevDecision.Adapter

      # Verifies the first sentence; while the second is verified the turn is
      # cancelled, so the reply ends after one spoken sentence.
      @impl true
      def decide_patient(%{candidate_text: candidate}) do
        if String.contains?(candidate, "REMÉDIO") do
          id = Application.fetch_env!(:backend, :completing_session_id)
          Backend.Stations.cancel_voice_turn(id, turn_id: 1)
        end

        {:ok, %{status: :verified}}
      end

      @impl true
      def decide_rubric(_request), do: {:error, :not_implemented}
    end

    defmodule SentenceStreamAdapter do
      @behaviour Backend.Stations.StationAI
      @impl true
      def next_reply(_package, _context), do: {:error, :no_regeneration}

      @impl true
      def stream_reply(_package, _context, on_text) do
        pieces = ["*(geme)* Começou ontem. ", "Tomei REMÉDIO", " ontem. ", "Ainda dói."]
        Enum.each(pieces, on_text)
        {:ok, %{text: Enum.join(pieces)}}
      end
    end

    defmodule MarkerRefusingJevAdapter do
      @behaviour Backend.Stations.JevDecision.Adapter

      @impl true
      def decide_patient(%{candidate_text: candidate}) do
        if String.contains?(candidate, "REMÉDIO"),
          do: {:ok, %{status: :semantic_refusal}},
          else: {:ok, %{status: :verified}}
      end

      @impl true
      def decide_rubric(_request), do: {:error, :not_implemented}
    end

    defp ndjson(conn),
      do: put_req_header(conn, "accept", "application/x-ndjson, application/json")

    defp lines(conn) do
      conn
      |> response(200)
      |> String.split("\n", trim: true)
      |> Enum.map(&Jason.decode!/1)
    end

    test "streams each verified sentence, then the result", %{conn: conn} do
      Application.put_env(:backend, :station_ai_adapter, SentenceStreamAdapter)
      id = Stations.create_session(%{audio_consent: true}).session_id

      conn = conn |> ndjson() |> post(transcripts_path(id), %{turn_id: 1, text: "Quando?"})

      assert ["application/x-ndjson" <> _] = get_resp_header(conn, "content-type")

      assert lines(conn) == [
               %{
                 "type" => "sentence",
                 "turn_id" => 1,
                 "generation_id" => 1,
                 "index" => 0,
                 "text" => "Começou ontem."
               },
               %{
                 "type" => "sentence",
                 "turn_id" => 1,
                 "generation_id" => 1,
                 "index" => 1,
                 "text" => "Tomei REMÉDIO ontem."
               },
               %{
                 "type" => "sentence",
                 "turn_id" => 1,
                 "generation_id" => 1,
                 "index" => 2,
                 "text" => "Ainda dói."
               },
               %{
                 "type" => "result",
                 "turn_id" => 1,
                 "generation_id" => 1,
                 "status" => "committed",
                 "reply_text" => "Começou ontem. Tomei REMÉDIO ontem. Ainda dói."
               }
             ]
    end

    test "a refused second sentence streams only the first", %{conn: conn} do
      Application.put_env(:backend, :station_ai_adapter, SentenceStreamAdapter)
      Application.put_env(:backend, :jev_decision_adapter, MarkerRefusingJevAdapter)
      id = Stations.create_session(%{audio_consent: true}).session_id

      conn = conn |> ndjson() |> post(transcripts_path(id), %{turn_id: 1, text: "Quando?"})
      body = response(conn, 200)

      refute body =~ "REMÉDIO"

      assert [%{"type" => "sentence", "text" => "Começou ontem."}, result] = lines(conn)

      assert result == %{
               "type" => "result",
               "turn_id" => 1,
               "generation_id" => 1,
               "status" => "committed",
               "reply_text" => "Começou ontem."
             }

      assert {:ok, %{messages: [_, %{role: :patient, text: "*(geme)* Começou ontem."}]}} =
               Stations.get_session(id)
    end

    test "a turn with nothing spoken answers like the single-reply form", %{conn: conn} do
      Application.put_env(:backend, :station_ai_adapter, TestSuccessAdapter)
      Application.put_env(:backend, :jev_decision_adapter, TestRefusingJevAdapter)
      id = Stations.create_session(%{audio_consent: true}).session_id

      conn = conn |> ndjson() |> post(transcripts_path(id), %{turn_id: 1, text: "Quando?"})

      assert json_response(conn, 201) == %{
               "turn_id" => 1,
               "status" => "kept",
               "generation_id" => 1,
               "addressee" => "patient"
             }

      conn = build_conn() |> put_req_header("authorization", "Bearer " <> @secret) |> ndjson()

      assert %{"status" => "duplicate"} =
               conn
               |> post(transcripts_path(id), %{turn_id: 1, text: "Quando?"})
               |> json_response(200)
    end

    test "errors before any sentence keep their status codes", %{conn: conn} do
      conn = ndjson(conn)

      assert %{"error" => "invalid_transcript"} =
               json_response(post(conn, transcripts_path("x"), %{turn_id: 1, text: " "}), 400)

      assert %{"error" => "session_not_found"} =
               json_response(
                 post(conn, transcripts_path("missing"), %{turn_id: 1, text: "Oi"}),
                 404
               )
    end

    test "an error after a streamed sentence ends the stream with an error line", %{conn: conn} do
      Application.put_env(:backend, :station_ai_adapter, SentenceStreamAdapter)
      id = Stations.create_session(%{audio_consent: true}).session_id
      # The session is completed by the user while the first sentence is handed over.
      Application.put_env(:backend, :jev_decision_adapter, CompletingJevAdapter)
      Application.put_env(:backend, :completing_session_id, id)
      on_exit(fn -> Application.delete_env(:backend, :completing_session_id) end)

      conn = conn |> ndjson() |> post(transcripts_path(id), %{turn_id: 1, text: "Quando?"})

      assert [%{"type" => "sentence", "index" => 0}, %{"type" => "error", "error" => error}] =
               lines(conn)

      assert error in ["stale_generation", "session_completed"]
    end
  end

  defp wait_until(fun, attempts \\ 100)

  defp wait_until(_fun, 0), do: flunk("condition not met in time")

  defp wait_until(fun, attempts) do
    if fun.() do
      :ok
    else
      Process.sleep(20)
      wait_until(fun, attempts - 1)
    end
  end

  describe "examiner-addressed voice turns (#274, #309)" do
    # The generation decides the addressee with its marker (#309).
    defmodule ExaminerMarkerAdapter do
      @behaviour Backend.Stations.StationAI

      @impl true
      def next_reply(_package, _context), do: {:ok, %{text: "[EXAMINADOR]"}}
    end

    defmodule ExaminerJevAdapter do
      @behaviour Backend.Stations.JevDecision.Adapter

      @impl true
      def decide_patient(_request), do: raise("no patient verification on the examiner path")

      @impl true
      def decide_rubric(_request), do: {:error, :not_implemented}
    end

    for stream? <- [false, true] do
      test "answers 201 kept with addressee examiner (streamed: #{stream?})", %{conn: conn} do
        Application.put_env(:backend, :station_ai_adapter, ExaminerMarkerAdapter)
        Application.put_env(:backend, :jev_decision_adapter, ExaminerJevAdapter)
        id = Stations.create_session(%{audio_consent: true}).session_id

        conn =
          if unquote(stream?),
            do: put_req_header(conn, "accept", "application/x-ndjson, application/json"),
            else: conn

        resp =
          conn
          |> post(transcripts_path(id), %{turn_id: 1, text: "Blumberg positivo."})
          |> json_response(201)

        assert resp == %{
                 "turn_id" => 1,
                 "status" => "kept",
                 "generation_id" => 1,
                 "addressee" => "examiner"
               }

        {:ok, stored} = Stations.get_session(id)
        assert [%{role: :learner, text: "Blumberg positivo."}] = stored.messages
      end
    end
  end

  describe "POST usage (#342)" do
    defp usage_path(id), do: ~p"/api/internal/voice/sessions/#{id}/usage"

    @report %{
      "report_id" => "AJ_job-1",
      "deepgram_audio_seconds" => 312.5,
      "elevenlabs_characters" => 1830,
      "livekit_participant_minutes" => 21.25
    }

    setup do
      previous = Application.get_env(:backend, Backend.Stations.Usage.Store)
      Application.put_env(:backend, Backend.Stations.Usage.Store, enabled: true)

      on_exit(fn ->
        if previous,
          do: Application.put_env(:backend, Backend.Stations.Usage.Store, previous),
          else: Application.delete_env(:backend, Backend.Stations.Usage.Store)
      end)
    end

    test "accepts the worker's audio usage and writes it into the finished session's row", %{
      conn: conn
    } do
      session = Stations.create_session(%{audio_consent: true})
      id = session.session_id
      {:ok, _} = Stations.complete_session(id, :user)

      assert %{"status" => "recorded"} = json_response(post(conn, usage_path(id), @report), 202)

      row = Backend.Repo.get!(Backend.Stations.Usage.SessionUsage, id)
      assert row.deepgram_audio_seconds == 312.5
      assert row.elevenlabs_characters == 1830
      assert row.livekit_participant_minutes == 21.25
      assert row.cost_by_provider["deepgram"] > 0
      assert row.cost_by_provider["elevenlabs"] > 0
      assert row.cost_by_provider["livekit"] > 0
    end

    test "a retried report replaces itself; reports of different jobs add up", %{conn: conn} do
      session = Stations.create_session(%{audio_consent: true})
      id = session.session_id

      assert json_response(post(conn, usage_path(id), @report), 202)
      assert json_response(post(conn, usage_path(id), @report), 202)

      second_job = %{@report | "report_id" => "AJ_job-2", "elevenlabs_characters" => 170}
      assert json_response(post(conn, usage_path(id), second_job), 202)

      voice = Backend.Stations.Usage.snapshot(id).voice
      assert voice.deepgram_audio_seconds == 625.0
      assert voice.elevenlabs_characters == 2000
      assert voice.livekit_participant_minutes == 42.5
    end

    test "an active session keeps the report until it is finished", %{conn: conn} do
      session = Stations.create_session(%{audio_consent: true})
      id = session.session_id

      assert json_response(post(conn, usage_path(id), @report), 202)
      assert Backend.Repo.get(Backend.Stations.Usage.SessionUsage, id) == nil

      {:ok, _} = Stations.complete_session(id, :user)

      assert Backend.Repo.get!(Backend.Stations.Usage.SessionUsage, id).elevenlabs_characters ==
               1830
    end

    test "rejects a malformed report without recording it", %{conn: conn} do
      session = Stations.create_session(%{audio_consent: true})
      id = session.session_id

      for bad <- [
            %{},
            Map.delete(@report, "report_id"),
            %{@report | "report_id" => ""},
            %{@report | "report_id" => String.duplicate("a", 129)},
            %{@report | "deepgram_audio_seconds" => -1},
            %{@report | "elevenlabs_characters" => 1.5},
            %{@report | "livekit_participant_minutes" => "many"},
            Map.delete(@report, "elevenlabs_characters")
          ] do
        assert %{"error" => "invalid_usage"} = json_response(post(conn, usage_path(id), bad), 400)
      end

      assert Backend.Stations.Usage.snapshot(id).voice.elevenlabs_characters == 0
    end

    test "answers 404 for an unknown session and 401 without the worker secret", %{conn: conn} do
      assert %{"error" => "session_not_found"} =
               json_response(post(conn, usage_path("missing"), @report), 404)

      assert %{"error" => "unauthorized"} =
               json_response(post(build_conn(), usage_path("missing"), @report), 401)
    end
  end
end
