defmodule Backend.Stations.TrainingOvertimeTest do
  use ExUnit.Case, async: false

  alias Backend.Stations.Conversation
  alias Backend.Stations.Overtime

  @learner %{role: :learner, modality: :text, text: "Pergunta"}

  setup do
    keys = [
      :station_duration_ms,
      :training_overtime_ms,
      :turn_grace_ms,
      :simulated_exam_evidence_window_ms
    ]

    previous = Map.new(keys, &{&1, Application.get_env(:backend, &1)})

    Application.put_env(:backend, :station_duration_ms, 40)
    Application.put_env(:backend, :training_overtime_ms, 200)
    Application.put_env(:backend, :turn_grace_ms, 50)
    # A simulated exam completes when its evidence window closes (#424).
    Application.put_env(:backend, :simulated_exam_evidence_window_ms, 0)

    on_exit(fn ->
      Enum.each(previous, fn
        {key, nil} -> Application.delete_env(:backend, key)
        {key, value} -> Application.put_env(:backend, key, value)
      end)
    end)
  end

  describe "a training past its expected end" do
    test "keeps accepting turns after deadline_at and before the cap" do
      session = Conversation.start()
      Process.sleep(80)

      assert {:ok, %{status: :active}} = Conversation.fetch(session.session_id)
      assert {:ok, _session, _token} = Conversation.begin_turn(session.session_id, @learner)
    end

    test "exposes cap_at after deadline_at and before expires_at" do
      session = Conversation.start()

      assert DateTime.diff(session.cap_at, session.deadline_at, :millisecond) == 200
      assert DateTime.compare(session.cap_at, session.expires_at) == :lt
    end

    test "is completed at the cap with reason :cap, then refuses turns with station_time_elapsed" do
      session = Conversation.start()
      Process.sleep(320)

      assert {:ok, completed} = Conversation.fetch(session.session_id)
      assert completed.status == :completed
      assert completed.completion_reason == :cap

      assert {:error, :station_time_elapsed} =
               Conversation.begin_turn(session.session_id, @learner)
    end

    test "a turn in flight at the cap keeps the existing grace window" do
      session = Conversation.start()
      Process.sleep(180)
      assert {:ok, _session, token} = Conversation.begin_turn(session.session_id, @learner)
      Process.sleep(80)

      assert {:ok, %{status: :active}} = Conversation.fetch(session.session_id)

      reply = %{role: :patient, modality: :text, text: "Resposta"}

      assert {:ok, resolved} =
               Conversation.resolve_turn(session.session_id, token, {:ok, reply})

      assert resolved.status == :completed
      assert resolved.completion_reason == :cap
      assert length(resolved.messages) == 2
    end

    test "the learner can still finish by hand with reason :user" do
      session = Conversation.start()
      Process.sleep(80)

      assert {:ok, completed} = Conversation.complete(session.session_id, :user)
      assert completed.completion_reason == :user
    end
  end

  describe "a real test (simulated exam)" do
    test "still ends at deadline_at with reason :timer and has no overtime" do
      session = Conversation.start(%{mode: :simulated_exam})
      assert session.cap_at == session.deadline_at
      Process.sleep(120)

      assert {:ok, completed} = Conversation.fetch(session.session_id)
      assert completed.completion_reason == :timer
      assert Overtime.seconds(completed) == nil
    end
  end

  describe "Overtime.seconds/1" do
    test "is zero when a training finishes within the expected time" do
      session = Conversation.start()
      assert {:ok, completed} = Conversation.complete(session.session_id, :user)
      assert Overtime.seconds(completed) == 0
    end

    test "counts whole seconds from deadline_at to completed_at" do
      deadline = ~U[2026-10-29 12:10:00Z]

      training = %{
        mode: :training,
        deadline_at: deadline,
        completed_at: DateTime.add(deadline, 200, :second)
      }

      assert Overtime.seconds(training) == 200
    end
  end

  describe "Overtime.penalty/1 in fortieths of a point" do
    for {seconds, fortieths} <- [{0, 0}, {1, 10}, {60, 10}, {61, 20}, {200, 40}, {600, 100}] do
      test "#{seconds} s costs #{fortieths} fortieths" do
        assert Overtime.penalty(unquote(seconds)) == unquote(fortieths)
      end
    end

    test "never exceeds 2.5 points, even with grace overtime past ten minutes" do
      assert Overtime.penalty(601) == 100
      assert Overtime.penalty(630) == 100
    end
  end

  describe "Overtime.training_score/2" do
    test "subtracts the penalty from the rubric total" do
      assert Overtime.training_score(200, 40) == 160
    end

    test "never goes below zero" do
      assert Overtime.training_score(20, 100) == 0
    end

    test "is nil when the rubric total is nil" do
      assert Overtime.training_score(nil, 40) == nil
    end
  end
end
