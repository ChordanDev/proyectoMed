defmodule Backend.ResultsFixtures do
  @moduledoc """
  Helpers for results history tests (#338): publish the reference case, swap
  the Jev decision adapter and play a finished session for a learner.
  """

  import ExUnit.Callbacks, only: [on_exit: 1]

  alias Backend.Content
  alias Backend.Stations
  alias Backend.Stations.Conversation

  @reference_case File.read!("priv/stations/acute-appendicitis/case.md")

  # Answers every rubric question as uncertain, so the attempt is graded with
  # no assessed criterion and `total` stays null (ADR-012 #124).
  defmodule UncertainDouble do
    @moduledoc false
    @behaviour Backend.Stations.JevDecision.Adapter
    def decide_patient(_), do: {:ok, %{status: :verified}}
    def decide_rubric(_), do: {:error, :not_implemented}

    def decide_rubric_batch(request) do
      {:ok, %{decisions: Enum.map(request.questions, &decision/1)}}
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

  # A technical failure of the decision provider invalidates the attempt.
  defmodule TechnicalFailureDouble do
    @moduledoc false
    @behaviour Backend.Stations.JevDecision.Adapter
    def decide_patient(_), do: {:error, :not_implemented}
    def decide_rubric(_), do: {:error, :not_implemented}
    def decide_rubric_batch(_), do: {:error, {:transport_error, "private-provider-detail"}}
  end

  @doc "Approves the reference case with `[ÁREA] area` and returns the case."
  def published_case_fixture(area \\ "Cirurgia Geral") do
    admin = Backend.AccountsFixtures.admin_fixture()
    markdown = String.replace(@reference_case, "[ÁREA] Cirurgia Geral", "[ÁREA] #{area}")
    {:ok, package} = Stations.parse_case(markdown)

    %{rows: [[id]]} =
      Backend.Repo.query!(
        "INSERT INTO cases (area, theme, markdown) VALUES ($1, $2, $3) RETURNING id",
        [area, package["theme"], markdown]
      )

    {:ok, kase} = Content.approve_case(Content.get_case!(id), package, admin)
    kase
  end

  @doc "Uses `adapter` as the Jev decision adapter until the test exits."
  def use_jev_adapter(adapter) do
    previous = Application.fetch_env(:backend, :jev_decision_adapter)
    Application.put_env(:backend, :jev_decision_adapter, adapter)

    on_exit(fn ->
      case previous do
        {:ok, value} -> Application.put_env(:backend, :jev_decision_adapter, value)
        :error -> Application.delete_env(:backend, :jev_decision_adapter)
      end
    end)
  end

  @doc """
  Starts a session of `user` on `kase`, sends one learner message and finishes
  it. Returns the session id.
  """
  def finished_session_fixture(user, kase) do
    {:ok, session} =
      Stations.start_station_session({:station, kase.number}, %{
        audio_consent: false,
        user_id: user && user.id
      })

    {:ok, _} =
      Conversation.append_message(session.session_id, %{
        role: :learner,
        modality: :text,
        text: "Onde começou a dor?"
      })

    {:ok, _} = Stations.complete_session(session.session_id)
    on_exit(fn -> Stations.discard_session(session.session_id) end)
    session.session_id
  end
end
