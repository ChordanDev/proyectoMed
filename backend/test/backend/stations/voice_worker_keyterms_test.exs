defmodule Backend.Stations.VoiceWorkerKeytermsTest do
  # Restarts the supervised Station Loader and edits application env: not async.
  use ExUnit.Case, async: false

  alias Backend.Stations
  alias Backend.Stations.StationLoader
  alias Backend.Stations.SttKeyterms

  setup do
    original = Application.fetch_env(:backend, :active_station_id)

    on_exit(fn ->
      case original do
        {:ok, value} -> Application.put_env(:backend, :active_station_id, value)
        :error -> Application.delete_env(:backend, :active_station_id)
      end

      restart_loader()
    end)

    :ok
  end

  test "acute-appendicitis voice context carries derived clinical keyterms without stt_keyterms" do
    keyterms = context_keyterms("acute-appendicitis")

    refute Map.has_key?(Stations.get_active_package(), "stt_keyterms")

    for term <- ["McBurney", "Blumberg", "palpação", "fossa ilíaca direita"] do
      assert term in keyterms, "expected #{inspect(term)} in #{inspect(keyterms)}"
    end

    assert length(keyterms) <= SttKeyterms.max_terms()
    assert SttKeyterms.estimated_tokens(keyterms) <= SttKeyterms.token_budget()
  end

  test "chest-pain voice context keeps its authored stt_keyterms first" do
    keyterms = context_keyterms("chest-pain-initial-assessment")
    explicit = Stations.get_active_package()["stt_keyterms"]

    assert Enum.take(keyterms, length(explicit)) == explicit
    assert length(keyterms) <= SttKeyterms.max_terms()
  end

  defp context_keyterms(station_id) do
    Application.put_env(:backend, :active_station_id, station_id)
    restart_loader()

    session = Stations.create_session(%{audio_consent: true})
    assert {:ok, %{keyterms: keyterms}} = Stations.voice_worker_context(session.session_id)
    keyterms
  end

  defp restart_loader do
    :ok = Supervisor.terminate_child(Backend.Supervisor, StationLoader)
    {:ok, _pid} = Supervisor.restart_child(Backend.Supervisor, StationLoader)
  end
end
