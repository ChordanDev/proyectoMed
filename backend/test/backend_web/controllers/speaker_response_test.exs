defmodule BackendWeb.SpeakerResponseTest do
  @moduledoc """
  Issue #341 left `speaker` out of the controller responses because the
  controllers belonged to #337: the text reply, the session transcript
  (`RefreshSession`) and the non-streamed voice receipt now name the actor who
  replied, `"patient"` or `"companion"`, and a reply with no stored speaker
  reads as `"patient"`.
  """
  use BackendWeb.ConnCase, async: false

  alias Backend.Stations

  @companion_case Path.expand("../../backend/stations/fixtures/case_format/companion.md", __DIR__)
  @secret "test-worker-secret"
  @question "Quando começou a febre?"
  @reply "A febre começou há dois dias."

  defmodule MarkedAI do
    @behaviour Backend.Stations.StationAI

    @impl true
    def next_reply(_package, _context),
      do:
        {:ok, %{text: Application.fetch_env!(:backend, :speaker_response_reply), used_facts: []}}
  end

  setup do
    keys = [
      :station_ai_adapter,
      :patient_verification,
      :voice_worker_secret,
      :speaker_response_reply
    ]

    previous = Map.new(keys, &{&1, Application.fetch_env(:backend, &1)})

    on_exit(fn ->
      Enum.each(previous, fn
        {key, {:ok, value}} -> Application.put_env(:backend, key, value)
        {key, :error} -> Application.delete_env(:backend, key)
      end)
    end)

    Application.put_env(:backend, :station_ai_adapter, MarkedAI)
    Application.put_env(:backend, :patient_verification, :off)
    Application.put_env(:backend, :voice_worker_secret, @secret)

    {:ok, package} = @companion_case |> File.read!() |> Stations.parse_case()
    %{package: package}
  end

  defp reply(text), do: Application.put_env(:backend, :speaker_response_reply, text)

  defp session(package, audio_consent) do
    Stations.create_session(%{
      package: package,
      audio_consent: audio_consent,
      station_slug: "companion",
      station_area: nil,
      station_theme: nil
    })
  end

  defp send_text(conn, id) do
    post(conn, ~p"/api/stations/active/sessions/#{id}/messages", %{
      "role" => "learner",
      "modality" => "text",
      "text" => @question
    })
  end

  describe "the text reply" do
    test "names the companion", %{conn: conn, package: package} do
      reply("[ACOMPANHANTE] " <> @reply)
      id = session(package, false).session_id

      assert %{"outcome" => "patient_reply", "reply_text" => @reply, "speaker" => "companion"} =
               conn |> send_text(id) |> json_response(200)
    end

    test "names the patient", %{conn: conn, package: package} do
      reply("[PACIENTE] Chora ao ser examinado.")
      id = session(package, false).session_id

      assert %{"speaker" => "patient"} = conn |> send_text(id) |> json_response(200)
    end

    test "of a single-actor station reads as the patient", %{conn: conn} do
      reply("Estou com febre.")
      id = Stations.create_session(%{audio_consent: false}).session_id

      assert %{"speaker" => "patient"} = conn |> send_text(id) |> json_response(200)
    end
  end

  describe "the session transcript" do
    test "names the speaker of each patient message", %{conn: conn, package: package} do
      reply("[ACOMPANHANTE] " <> @reply)
      id = session(package, false).session_id
      send_text(conn, id)

      assert %{"messages" => [learner, patient]} =
               conn |> get(~p"/api/stations/active/sessions/#{id}") |> json_response(200)

      assert %{"role" => "patient", "text" => @reply, "speaker" => "companion"} = patient
      refute Map.has_key?(learner, "speaker")
    end

    test "reads a message with no stored speaker as the patient", %{conn: conn} do
      reply("Estou com febre.")
      id = Stations.create_session(%{audio_consent: false}).session_id
      send_text(conn, id)

      assert %{"messages" => [_learner, %{"role" => "patient", "speaker" => "patient"}]} =
               conn |> get(~p"/api/stations/active/sessions/#{id}") |> json_response(200)
    end
  end

  describe "the non-streamed voice receipt" do
    test "names the companion", %{conn: conn, package: package} do
      reply("[ACOMPANHANTE] " <> @reply)
      id = session(package, true).session_id

      conn =
        conn
        |> put_req_header("authorization", "Bearer " <> @secret)
        |> post(~p"/api/internal/voice/sessions/#{id}/transcripts", %{
          turn_id: 1,
          text: @question
        })

      assert %{"status" => "committed", "reply_text" => @reply, "speaker" => "companion"} =
               json_response(conn, 201)
    end

    test "of a single-actor station reads as the patient", %{conn: conn} do
      reply("Estou com febre.")
      id = Stations.create_session(%{audio_consent: true}).session_id

      conn =
        conn
        |> put_req_header("authorization", "Bearer " <> @secret)
        |> post(~p"/api/internal/voice/sessions/#{id}/transcripts", %{
          turn_id: 1,
          text: @question
        })

      assert %{"status" => "committed", "speaker" => "patient"} = json_response(conn, 201)
    end
  end
end
