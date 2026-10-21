defmodule Backend.Stations.StationAIMarkerTest do
  @moduledoc """
  Issue #309: `StationAI.next_reply/2` (the CandidateGate's regeneration) strips
  the addressee marker before BoundedReply, so it never reaches the learner.
  """
  use ExUnit.Case, async: false

  alias Backend.Stations.StationAI

  defmodule MarkedAI do
    @behaviour Backend.Stations.StationAI

    @impl true
    def next_reply(_package, _context),
      do: {:ok, %{text: Application.fetch_env!(:backend, :marker_test_reply)}}
  end

  setup do
    previous =
      Map.new(
        [:station_ai_adapter, :marker_test_reply],
        &{&1, Application.fetch_env(:backend, &1)}
      )

    on_exit(fn ->
      Enum.each(previous, fn
        {key, {:ok, value}} -> Application.put_env(:backend, key, value)
        {key, :error} -> Application.delete_env(:backend, key)
      end)
    end)

    Application.put_env(:backend, :station_ai_adapter, MarkedAI)
    %{package: Backend.Stations.get_active_package()}
  end

  test "a patient marker is stripped", %{package: package} do
    Application.put_env(:backend, :marker_test_reply, "[PACIENTE] A dor começou ontem à noite.")

    assert {:ok, %{text: "A dor começou ontem à noite."}} =
             StationAI.next_reply(package, %{conversation: [], language: "pt-BR"})
  end

  test "a reply without a marker is kept whole", %{package: package} do
    Application.put_env(:backend, :marker_test_reply, "A dor começou ontem à noite.")

    assert {:ok, %{text: "A dor começou ontem à noite."}} =
             StationAI.next_reply(package, %{conversation: [], language: "pt-BR"})
  end

  test "an examiner marker never reaches the reply text", %{package: package} do
    Application.put_env(:backend, :marker_test_reply, "[EXAMINADOR]")

    assert {:ok, %{text: text}} =
             StationAI.next_reply(package, %{conversation: [], language: "pt-BR"})

    refute text =~ "EXAMINADOR"
  end
end
