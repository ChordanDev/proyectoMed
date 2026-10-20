defmodule BackendWeb.EducationalResultTest do
  use BackendWeb.ConnCase, async: false

  alias Backend.Stations
  alias Backend.Stations.StationLoader

  defmodule PartialDouble do
    @behaviour Backend.Stations.JevDecision.Adapter
    def decide_patient(_), do: {:ok, %{status: :verified}}
    def decide_rubric(_), do: {:error, :not_implemented}

    def decide_rubric_batch(request) do
      answers =
        Application.get_env(:backend, __MODULE__, %{"criterion-a" => "parcialmente_adequado"})

      {:ok,
       %{
         decisions:
           Enum.map(request.questions, fn question ->
             classification = Map.get(answers, question.criterion.id, "uncertain")

             evidence_ids =
               if(classification in ["uncertain", "inadequado"], do: [], else: ["turn-1"])

             %{
               criterion_id: question.criterion.id,
               classification: classification,
               evidence_ids: evidence_ids,
               actions:
                 Enum.map(
                   question.actions,
                   &%{id: &1.id, classification: "performed", evidence_ids: evidence_ids}
                 )
             }
           end)
       }}
    end
  end

  # The 2026-10-20 rehearsal (issue #291): on the appendicitis item 2 the
  # learner asked the initial location (turn-1) and the duration (turn-3) and
  # nothing else, and the migration stayed undecided.
  defmodule RehearsalDouble do
    @behaviour Backend.Stations.JevDecision.Adapter
    def decide_patient(_), do: {:ok, %{status: :verified}}
    def decide_rubric(_), do: {:error, :not_implemented}

    @item_two %{
      "criterio-1" => {"performed", ["turn-1"]},
      "criterio-2" => {"uncertain", []},
      "criterio-4" => {"performed", ["turn-3"]}
    }

    def decide_rubric_batch(request) do
      {:ok, %{decisions: Enum.map(request.questions, &decision/1)}}
    end

    defp decision(%{criterion: %{id: "item-02"}} = question) do
      %{
        criterion_id: "item-02",
        classification: "uncertain",
        evidence_ids: ["turn-1"],
        actions:
          Enum.map(question.actions, fn %{id: id} ->
            {classification, evidence_ids} = Map.get(@item_two, id, {"not_performed", []})
            %{id: id, classification: classification, evidence_ids: evidence_ids}
          end)
      }
    end

    defp decision(question) do
      %{
        criterion_id: question.criterion.id,
        classification: "uncertain",
        evidence_ids: [],
        actions:
          Enum.map(question.actions, &%{id: &1.id, classification: "uncertain", evidence_ids: []})
      }
      |> Map.merge(if question[:enumerate_answers], do: %{answers: []}, else: %{})
    end
  end

  defmodule TechnicalFailureDouble do
    @behaviour Backend.Stations.JevDecision.Adapter
    def decide_patient(_), do: {:error, :not_implemented}
    def decide_rubric(_), do: {:error, :not_implemented}
    def decide_rubric_batch(_), do: {:error, {:transport_error, "private-provider-detail"}}
  end

  defmodule FeedbackDouble do
    @behaviour Backend.Stations.LearnerFeedback.Adapter

    @impl true
    def write_feedback(request) do
      send(Application.fetch_env!(:backend, __MODULE__), {:feedback_request, request})
      {:ok, Map.new(request.criteria, &{&1.id, "Feedback for #{&1.id}."})}
    end
  end

  setup do
    package = Stations.get_active_package()
    adapter = Application.fetch_env(:backend, :jev_decision_adapter)

    fixture =
      File.read!("priv/stations/fixtures/valid-package-v2-partial-reconciliation.json")
      |> Jason.decode!()

    :sys.replace_state(StationLoader, fn _ -> fixture end)
    Application.put_env(:backend, :jev_decision_adapter, PartialDouble)

    on_exit(fn ->
      Application.delete_env(:backend, PartialDouble)
      :sys.replace_state(StationLoader, fn _ -> package end)

      case adapter do
        {:ok, value} -> Application.put_env(:backend, :jev_decision_adapter, value)
        :error -> Application.delete_env(:backend, :jev_decision_adapter)
      end
    end)

    session = Stations.create_session(audio_consent: false)

    {:ok, _} =
      Backend.Stations.Conversation.append_message(session.session_id, %{
        role: :learner,
        modality: :text,
        text: "Exemplo da sessão"
      })

    {:ok, _} = Stations.complete_session(session.session_id)
    on_exit(fn -> Stations.discard_session(session.session_id) end)
    %{session_id: session.session_id}
  end

  test "v2 exposes exact partial coverage and authored metadata without diagnostics", %{
    conn: conn,
    session_id: id
  } do
    response = get(conn, "/api/v2/stations/active/sessions/#{id}/result")
    assert get_resp_header(response, "cache-control") == ["no-store"]
    body = json_response(response, 200)
    assert body["schema_version"] == "2"
    assert body["placeholder"] == true

    assert body["estimates"] == %{
             "total" => nil,
             "scored_subtotal" => "0.25",
             "scored_max" => "0.25",
             "eligible_max" => "1.25",
             "unresolved" => [%{"id" => "criterion-b", "status" => "uncertain"}]
           }

    assert body["coverage"] == %{
             "assessed" => 1,
             "uncertain" => 1,
             "not_observable" => 0,
             "not_applicable" => 0
           }

    assert [assessed, uncertain] = body["criteria"]
    assert assessed["description"] == "Criterion with an observed partial result."
    assert assessed["level_description"] == "Criterion A is partially adequate."
    assert assessed["points"] == "0.25"

    assert assessed["evidence"] == [
             %{"id" => "turn-1", "role" => "learner", "text" => "Exemplo da sessão"}
           ]

    refute Map.has_key?(uncertain, "points")
    refute Map.has_key?(uncertain, "level")
    refute Map.has_key?(body, "calls")
    refute Map.has_key?(assessed, "sub_actions")
  end

  test "v2 replaces only assessed recommendations with generated feedback", %{
    conn: conn,
    session_id: id
  } do
    authored = conn |> get("/api/v2/stations/active/sessions/#{id}/result") |> json_response(200)
    previous = Application.fetch_env(:backend, :learner_feedback_adapter)
    Application.put_env(:backend, :learner_feedback_adapter, FeedbackDouble)
    Application.put_env(:backend, FeedbackDouble, self())

    on_exit(fn ->
      Application.delete_env(:backend, FeedbackDouble)

      case previous do
        {:ok, value} -> Application.put_env(:backend, :learner_feedback_adapter, value)
        :error -> Application.delete_env(:backend, :learner_feedback_adapter)
      end
    end)

    body = conn |> get("/api/v2/stations/active/sessions/#{id}/result") |> json_response(200)
    assert_received {:feedback_request, request}
    assert Enum.map(request.criteria, & &1.id) == ["criterion-a"]

    assert [assessed, uncertain] = body["criteria"]
    assert assessed["recommendation"] == "Feedback for criterion-a."
    assert uncertain["recommendation"] == "Gather enough evidence for criterion B."

    drop = fn result ->
      update_in(result["criteria"], fn criteria ->
        Enum.map(criteria, &Map.delete(&1, "recommendation"))
      end)
    end

    assert drop.(body) == drop.(authored)
    assert body["estimates"] == authored["estimates"]
    assert body["coverage"] == authored["coverage"]

    assert conn |> get("/api/v2/stations/active/sessions/#{id}/result") |> json_response(200) ==
             body

    refute_received {:feedback_request, _}
  end

  test "provider transport errors expose only an invalid attempt, never diagnostics or partial points",
       %{conn: conn, session_id: id} do
    Application.put_env(:backend, :jev_decision_adapter, TechnicalFailureDouble)
    body = conn |> get("/api/v2/stations/active/sessions/#{id}/result") |> json_response(502)
    assert body["error"] == "invalid_attempt"
    assert Enum.sort(Map.keys(body)) == ["error", "message"]
    refute Jason.encode!(body) =~ "private-provider-detail"
    assert {:ok, session} = Stations.get_session(id)
    refute Map.has_key?(session, :assessment)
    :ok = Stations.discard_session(id)
    assert {:error, :not_found} = Stations.get_educational_result(id)
  end

  test "an uncertain item shows its evidence and a recommendation, not its title", %{
    conn: conn
  } do
    package = File.read!("priv/stations/acute-appendicitis/package.json") |> Jason.decode!()
    :sys.replace_state(StationLoader, fn _ -> package end)
    Application.put_env(:backend, :jev_decision_adapter, RehearsalDouble)
    session = Stations.create_session(audio_consent: false)
    on_exit(fn -> Stations.discard_session(session.session_id) end)

    for {role, text} <- [
          learner: "Onde começou a dor?",
          patient: "Em volta do umbigo.",
          learner: "Há quanto tempo está com essa dor?"
        ] do
      {:ok, _} =
        Backend.Stations.Conversation.append_message(session.session_id, %{
          role: role,
          modality: :text,
          text: text
        })
    end

    {:ok, _} = Stations.complete_session(session.session_id)

    body =
      conn
      |> get("/api/v2/stations/active/sessions/#{session.session_id}/result")
      |> json_response(200)

    item = Enum.find(body["criteria"], &(&1["id"] == "item-02"))

    assert item["status"] == "uncertain"
    refute Map.has_key?(item, "points")
    refute item["recommendation"] == "Anamnese — caracterização da dor"

    assert item["recommendation"] ==
             "Você investigou: Localização inicial; tempo de evolução. " <>
               "Ainda falta investigar: migração para fossa ilíaca direita; " <>
               "caráter e progressão; intensidade; fatores de piora ou melhora."

    assert item["evidence_ids"] == ["turn-1", "turn-3"]

    assert Enum.map(item["evidence"], &{&1["id"], &1["role"], &1["text"]}) == [
             {"turn-1", "learner", "Onde começou a dor?"},
             {"turn-3", "learner", "Há quanto tempo está com essa dor?"}
           ]

    assert item["id"] in Enum.map(body["estimates"]["unresolved"], & &1["id"])
  end

  defp install_fixture do
    fixture = File.read!("priv/stations/fixtures/valid-package-v2.json") |> Jason.decode!()
    :sys.replace_state(StationLoader, fn _ -> fixture end)
    fixture
  end

  test "genuine zero is assessed, while unobservable and excluded have no score", %{
    conn: conn,
    session_id: id
  } do
    install_fixture()

    Application.put_env(:backend, PartialDouble, %{
      "onset-assessment" => "inadequado",
      "symptom-characterization" => "uncertain"
    })

    body = conn |> get("/api/v2/stations/active/sessions/#{id}/result") |> json_response(200)
    assert [zero, uncertain, unobservable, excluded] = body["criteria"]
    assert zero["points"] == "0"
    assert zero["level"] == "inadequado"
    assert zero["status"] == "assessed"
    assert uncertain["status"] == "uncertain"
    assert unobservable["status"] == "not_observable"
    assert unobservable["reason"] == "required_modality_unavailable"
    assert excluded["status"] == "not_applicable"
    assert excluded["reason"] == "authored_exclusion"

    for criterion <- [uncertain, unobservable, excluded] do
      refute Map.has_key?(criterion, "points")
      refute Map.has_key?(criterion, "level")
    end

    assert body["estimates"]["total"] == nil
    assert body["estimates"]["scored_subtotal"] == "0"
    assert body["estimates"]["scored_max"] == "1"
    assert body["estimates"]["eligible_max"] == "2.25"
  end

  test "complete coverage yields an exact 1.125 of 1.5 without rescaling", %{
    conn: conn,
    session_id: id
  } do
    fixture = install_fixture()
    [onset, symptom | _] = fixture["rubric"]
    extra = Map.put(symptom, "id", "extra")

    fixture =
      fixture |> Map.put("rubric", [onset, symptom, extra]) |> Map.put("placeholder", false)

    :sys.replace_state(StationLoader, fn _ -> fixture end)

    Application.put_env(:backend, PartialDouble, %{
      "onset-assessment" => "adequado",
      "symptom-characterization" => "parcialmente_adequado",
      "extra" => "inadequado"
    })

    body = conn |> get("/api/v2/stations/active/sessions/#{id}/result") |> json_response(200)
    assert body["placeholder"] == false

    assert body["estimates"] == %{
             "total" => "1.125",
             "scored_subtotal" => "1.125",
             "scored_max" => "1.5",
             "eligible_max" => "1.5",
             "unresolved" => []
           }
  end

  test "empty and all excluded rubrics have no total", %{conn: conn, session_id: id} do
    fixture = install_fixture()

    for rubric <- [[], Enum.map(fixture["rubric"], &Map.put(&1, "exclusion", true))] do
      :sys.replace_state(StationLoader, fn _ -> Map.put(fixture, "rubric", rubric) end)
      body = conn |> get("/api/v2/stations/active/sessions/#{id}/result") |> json_response(200)

      assert body["estimates"] == %{
               "total" => nil,
               "scored_subtotal" => "0",
               "scored_max" => "0",
               "eligible_max" => "0",
               "unresolved" => []
             }
    end
  end

  test "disabled provider invalidates v2 without detail or fallback but legacy remains score-free",
       %{conn: conn, session_id: id} do
    Application.put_env(
      :backend,
      :jev_decision_adapter,
      Backend.Stations.JevDecision.DisabledAdapter
    )

    body = conn |> get("/api/v2/stations/active/sessions/#{id}/result") |> json_response(502)
    assert Map.keys(body) |> Enum.sort() == ["error", "message"]
    assert body["error"] == "invalid_attempt"
    legacy = conn |> get("/api/stations/active/sessions/#{id}/result") |> json_response(200)

    assert Enum.all?(legacy["criteria"], fn criterion ->
             Enum.sort(Map.keys(criterion)) == ["evidence", "id", "recommendation", "status"]
           end)
  end

  test "v2 preserves unfinished, missing, expired and discarded session errors", %{conn: conn} do
    session = Stations.create_session(audio_consent: false)

    assert conn
           |> get("/api/v2/stations/active/sessions/#{session.session_id}/result")
           |> json_response(422)
           |> Map.get("error") == "session_not_finished"

    assert conn
           |> get("/api/v2/stations/active/sessions/missing/result")
           |> json_response(404)
           |> Map.get("error") == "session_not_found"

    previous = Application.fetch_env(:backend, :conversation_timeout_ms)
    Application.put_env(:backend, :conversation_timeout_ms, 0)
    expired = Stations.create_session(audio_consent: false)

    case previous do
      {:ok, value} -> Application.put_env(:backend, :conversation_timeout_ms, value)
      :error -> Application.delete_env(:backend, :conversation_timeout_ms)
    end

    assert conn
           |> get("/api/v2/stations/active/sessions/#{expired.session_id}/result")
           |> json_response(410)
           |> Map.get("error") == "session_expired"

    Stations.discard_session(session.session_id)

    assert conn
           |> get("/api/v2/stations/active/sessions/#{session.session_id}/result")
           |> json_response(404)
           |> Map.get("error") == "session_not_found"
  end
end
