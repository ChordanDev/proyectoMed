defmodule Backend.Release.FlyTomlTest do
  @moduledoc """
  The deploy settings of `fly.toml` that the drain gate relies on (#344).
  """

  use ExUnit.Case, async: true

  @fly_toml File.read!(Path.expand("../../../fly.toml", __DIR__))

  defp setting(key),
    do: Regex.run(~r/^\s*#{key}\s*=\s*(.+?)\s*$/m, @fly_toml, capture: :all_but_first)

  test "runs one machine in São Paulo with the longest stop timeout" do
    assert setting("primary_region") == [~s("gru")]
    assert setting("kill_timeout") == ["300"]
    assert setting("min_machines_running") == ["1"]
    assert setting("auto_stop_machines") == [~s("off")]
  end

  test "migrates before the deploy and deploys bluegreen behind the health check" do
    assert setting("release_command") == [~s("/app/bin/migrate")]
    assert setting("strategy") == [~s("bluegreen")]
    assert setting("path") == [~s("/health")]
    assert File.exists?(Path.expand("../../../rel/overlays/bin/migrate", __DIR__))
  end

  test "sets the non-secret environment" do
    assert setting("PHX_HOST")
    assert setting("TRUSTED_CLIENT_IP_HEADER") == [~s("fly-client-ip")]
    assert setting("VOICE_PROVIDER") == [~s("deepgram_cartesia")]
    refute @fly_toml =~ ~r/(API_KEY|SECRET|PASSWORD|DATABASE_URL)\s*=/
  end
end
