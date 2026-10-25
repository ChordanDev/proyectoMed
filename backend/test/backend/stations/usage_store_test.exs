defmodule Backend.Stations.UsageStoreTest do
  @moduledoc """
  One content-free usage row per finished session (issue #342), and the
  median cost per station over a period.
  """

  # Session state lives in the shared Conversation table: not async.
  use Backend.DataCase, async: false

  alias Backend.Content
  alias Backend.Stations
  alias Backend.Stations.Usage
  alias Backend.Stations.Usage.SessionUsage

  @reference_case File.read!(
                    Path.expand("../../../priv/stations/acute-appendicitis/case.md", __DIR__)
                  )
  @learner_text "Bom dia, quando começou a dor abdominal?"

  defmodule RecordingAdapter do
    @moduledoc false
    @behaviour Backend.Stations.StationAI

    # Stands in for a Claude-backed patient: records what one call would bill.
    @impl true
    def next_reply(_package, _context) do
      Backend.Stations.Usage.record_claude("claude-haiku-5-5", %{
        "input_tokens" => 100,
        "output_tokens" => 40,
        "cache_read_input_tokens" => 3_000,
        "cache_creation_input_tokens" => 0
      })

      {:ok, %{text: "Começou ontem à noite."}}
    end
  end

  setup do
    previous_adapter = Application.get_env(:backend, :station_ai_adapter)
    previous_store = Application.get_env(:backend, Backend.Stations.Usage.Store)
    Application.put_env(:backend, :station_ai_adapter, RecordingAdapter)
    Application.put_env(:backend, Backend.Stations.Usage.Store, enabled: true)

    on_exit(fn ->
      restore(:station_ai_adapter, previous_adapter)
      restore(Backend.Stations.Usage.Store, previous_store)
    end)

    admin = Backend.AccountsFixtures.admin_fixture()
    {:ok, package} = Stations.parse_case(@reference_case)

    %{rows: [[id]]} =
      Repo.query!(
        "INSERT INTO cases (area, theme, markdown) VALUES ($1, $2, $3) RETURNING id",
        ["Cirurgia Geral", "Tema", @reference_case]
      )

    {:ok, kase} =
      Content.approve_case(
        Content.get_case!(id),
        Map.put(package, "area", "Cirurgia Geral"),
        admin
      )

    %{kase: kase}
  end

  defp restore(key, nil), do: Application.delete_env(:backend, key)
  defp restore(key, value), do: Application.put_env(:backend, key, value)

  defp start!(kase) do
    {:ok, session} = Stations.start_station_session({:station, kase.number}, %{})
    session.session_id
  end

  describe "persisting finished sessions" do
    test "a finished session has one row with its usage per provider and an estimated cost",
         %{kase: kase} do
      id = start!(kase)
      Stations.create_message(id, %{role: :learner, text: @learner_text})
      Usage.track(id, fn -> Usage.record_jev_call() end)

      assert Repo.get(SessionUsage, id) == nil
      assert {:ok, _session} = Stations.complete_session(id, :user)

      row = Repo.get!(SessionUsage, id)
      assert row.station_id == Integer.to_string(kase.number)
      assert row.station_version == "1"

      assert row.station_version_id ==
               Stations.get_session(id) |> elem(1) |> Map.get(:station_version_id)

      assert %DateTime{} = row.started_at
      assert %DateTime{} = row.finished_at

      assert %{"claude-haiku-5-5" => %{"input_tokens" => input, "output_tokens" => output}} =
               row.claude_usage

      assert input >= 100 and output >= 40
      assert row.jev_calls >= 1
      assert row.deepgram_audio_seconds == 0.0
      assert row.elevenlabs_characters == 0
      assert row.livekit_participant_minutes == 0.0

      assert Map.keys(row.cost_by_provider) |> Enum.sort() ==
               ["claude", "deepgram", "elevenlabs", "jev", "livekit"]

      assert row.cost_by_provider["claude"] > 0
      assert Decimal.gt?(row.estimated_cost_usd, 0)
      assert row.unpriced_models == []
    end

    test "finishing again or reading the result updates the same row", %{kase: kase} do
      id = start!(kase)
      {:ok, _} = Stations.complete_session(id, :user)
      first = Repo.get!(SessionUsage, id)

      Usage.track(id, fn ->
        Usage.record_claude("claude-opus-5-5", %{"input_tokens" => 2_000, "output_tokens" => 500})
      end)

      {:ok, _} = Stations.complete_session(id, :user)
      _ = Stations.get_educational_result(id)

      assert Repo.aggregate(SessionUsage, :count) == 1
      updated = Repo.get!(SessionUsage, id)
      assert updated.claude_usage["claude-opus-5-5"]["input_tokens"] == 2_000
      assert Decimal.gt?(updated.estimated_cost_usd, first.estimated_cost_usd)
    end

    test "an active session has no row", %{kase: kase} do
      id = start!(kase)
      Stations.create_message(id, %{role: :learner, text: @learner_text})
      assert Repo.get(SessionUsage, id) == nil
    end

    test "the store writes nothing when disabled (the test default)", %{kase: kase} do
      Application.put_env(:backend, Backend.Stations.Usage.Store, enabled: false)
      id = start!(kase)
      {:ok, _} = Stations.complete_session(id, :user)
      assert Repo.get(SessionUsage, id) == nil
    end
  end

  describe "content-free rows (ADR-001/009)" do
    test "the table holds counts, costs and station identity only: no user id and no content" do
      %{rows: rows} =
        Repo.query!(
          "SELECT column_name FROM information_schema.columns WHERE table_name = 'session_usages'"
        )

      assert rows |> List.flatten() |> Enum.sort() ==
               Enum.sort([
                 "session_id",
                 "station_id",
                 "station_version",
                 "station_version_id",
                 "started_at",
                 "finished_at",
                 "claude_usage",
                 "jev_calls",
                 "deepgram_audio_seconds",
                 "elevenlabs_characters",
                 "livekit_participant_minutes",
                 "cost_by_provider",
                 "unpriced_models",
                 "estimated_cost_usd",
                 "inserted_at",
                 "updated_at"
               ])
    end

    test "the stored row never carries the conversation text", %{kase: kase} do
      id = start!(kase)
      Stations.create_message(id, %{role: :learner, text: @learner_text})
      {:ok, _} = Stations.complete_session(id, :user)

      %{rows: [[row_json]]} =
        Repo.query!("SELECT row_to_json(u)::text FROM session_usages u WHERE session_id = $1", [
          id
        ])

      refute row_json =~ "dor abdominal"
      refute row_json =~ "Começou ontem"
    end
  end

  describe "session_cost_report/2" do
    defp insert_row!(station_id, cost, finished_at) do
      Repo.insert!(%SessionUsage{
        session_id: Ecto.UUID.generate(),
        station_id: station_id,
        station_version: "1",
        started_at: DateTime.add(finished_at, -600, :second),
        finished_at: finished_at,
        claude_usage: %{},
        jev_calls: 0,
        deepgram_audio_seconds: 0.0,
        elevenlabs_characters: 0,
        livekit_participant_minutes: 0.0,
        cost_by_provider: %{},
        unpriced_models: [],
        estimated_cost_usd: Decimal.new(cost)
      })
    end

    test "gives the median cost per station for the sessions finished in the period" do
      day = ~U[2026-10-24 00:00:00.000000Z]
      noon = DateTime.add(day, 12 * 3600, :second)

      insert_row!("12", "0.010000", noon)
      insert_row!("12", "0.020000", noon)
      insert_row!("12", "0.100000", noon)
      insert_row!("7", "0.010000", noon)
      insert_row!("7", "0.030000", noon)
      # Outside the day: the day before and the next midnight.
      insert_row!("12", "5.000000", DateTime.add(day, -1, :second))
      insert_row!("7", "5.000000", DateTime.add(day, 24 * 3600, :second))

      assert Stations.session_cost_report(day, DateTime.add(day, 24 * 3600, :second)) == [
               %{
                 station_id: "12",
                 sessions: 3,
                 median_cost_usd: 0.02,
                 total_cost_usd: 0.13
               },
               %{
                 station_id: "7",
                 sessions: 2,
                 median_cost_usd: 0.02,
                 total_cost_usd: 0.04
               }
             ]
    end

    test "is empty for a period without finished sessions" do
      assert Stations.session_cost_report(~U[2020-01-01 00:00:00Z], ~U[2020-01-02 00:00:00Z]) ==
               []
    end
  end
end
