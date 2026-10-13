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

  defmodule TechnicalFailureDouble do
    @behaviour Backend.Stations.JevDecision.Adapter
    def decide_patient(_), do: {:error, :not_implemented}
    def decide_rubric(_), do: {:error, :not_implemented}
    def decide_rubric_batch(_), do: {:error, {:transport_error, "private-provider-detail"}}
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
