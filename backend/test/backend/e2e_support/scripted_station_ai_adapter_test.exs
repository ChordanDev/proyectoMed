defmodule Backend.E2ESupport.ScriptedStationAIAdapterTest do
  use BackendWeb.ConnCase, async: false

  alias Backend.E2ESupport.{ApprovingJevAdapter, ScriptedStationAIAdapter}

  # The adapter is selected together with `ApprovingJevAdapter` by a process
  # that cannot inject adapters, so this test drives the real HTTP contract the
  # Unreal station client uses, not only the adapter's raw shape.
  setup do
    previous =
      for key <- [:station_ai_adapter, :jev_decision_adapter],
          do: {key, Application.fetch_env(:backend, key)}

    Application.put_env(:backend, :station_ai_adapter, ScriptedStationAIAdapter)
    Application.put_env(:backend, :jev_decision_adapter, ApprovingJevAdapter)

    on_exit(fn ->
      for {key, value} <- previous do
        case value do
          {:ok, adapter} -> Application.put_env(:backend, key, adapter)
          :error -> Application.delete_env(:backend, key)
        end
      end
    end)
  end

  test "answers a typed turn with its scripted patient reply", %{conn: conn} do
    %{"session_id" => session_id} =
      conn
      |> post(~p"/api/stations/active/sessions", %{"audio_consent" => false})
      |> json_response(200)

    reply =
      build_conn()
      |> post(~p"/api/stations/active/sessions/#{session_id}/messages", %{
        "role" => "learner",
        "modality" => "text",
        "text" => "Bom dia, como o senhor está?"
      })
      |> json_response(200)

    assert %{"outcome" => "patient_reply", "reply_text" => reply_text} = reply
    assert reply_text == ScriptedStationAIAdapter.reply_text()
  end

  test "reads nothing of the package or the conversation" do
    assert {:ok, %{text: "[PACIENTE] " <> text}} = ScriptedStationAIAdapter.next_reply(%{}, %{})
    assert text == ScriptedStationAIAdapter.reply_text()
  end
end
