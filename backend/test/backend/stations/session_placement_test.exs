defmodule Backend.Stations.SessionPlacementTest do
  @moduledoc """
  Conversations live in the memory of the machine that started them (#344), so
  a session id names its owning Fly machine (`FLY_MACHINE_ID`) and a request
  that reaches another machine during a deploy is replayed to the owner.
  """

  # Mutates the node-wide machine id.
  use Backend.DataCase, async: false

  alias Backend.Stations

  setup do
    previous = Application.fetch_env(:backend, :machine_id)

    on_exit(fn ->
      case previous do
        {:ok, value} -> Application.put_env(:backend, :machine_id, value)
        :error -> Application.delete_env(:backend, :machine_id)
      end
    end)

    :ok
  end

  test "a session started on a Fly machine records and names its owner" do
    Application.put_env(:backend, :machine_id, "e2865013b45e78")

    session = Stations.create_session(audio_consent: false)

    assert session.owner_machine_id == "e2865013b45e78"
    assert ["e2865013b45e78", random] = String.split(session.session_id, ".")
    assert byte_size(random) == 22
    assert {:ok, _session} = Stations.get_session(session.session_id)
    assert Stations.session_placement(session.session_id) == :local
  end

  test "without a machine id the session id is unchanged" do
    Application.delete_env(:backend, :machine_id)

    session = Stations.create_session(audio_consent: false)

    assert session.owner_machine_id == nil
    refute session.session_id =~ "."
    assert byte_size(session.session_id) == 22
  end

  test "a session owned by another machine is replayed to it" do
    Application.put_env(:backend, :machine_id, "e2865013b45e78")

    assert Stations.session_placement("3d8d9e1b2c4a77.AAAAAAAAAAAAAAAAAAAAAA") ==
             {:replay, "3d8d9e1b2c4a77"}
  end

  test "anything else is answered locally" do
    Application.put_env(:backend, :machine_id, "e2865013b45e78")

    for id <- ["AAAAAAAAAAAAAAAAAAAAAA", "e2865013b45e78.AAAA", ".AAAA", "BAD ID!.AAAA", "a.b.c"] do
      assert Stations.session_placement(id) == :local, "expected #{inspect(id)} to be local"
    end

    Application.delete_env(:backend, :machine_id)
    assert Stations.session_placement("3d8d9e1b2c4a77.AAAA") == :local
  end
end
