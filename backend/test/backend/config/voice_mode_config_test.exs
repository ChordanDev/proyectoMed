defmodule Backend.Config.VoiceModeConfigTest do
  # Reads config/runtime.exs with a controlled environment: not async, because the
  # operating system environment is global.
  use ExUnit.Case, async: false

  @runtime_config Path.expand("../../../config/runtime.exs", __DIR__)
  @variables ~w(VOICE_MODE LIVEKIT_URL LIVEKIT_API_KEY LIVEKIT_API_SECRET)
  @livekit %{
    "LIVEKIT_URL" => "ws://127.0.0.1:7880",
    "LIVEKIT_API_KEY" => "devkey",
    "LIVEKIT_API_SECRET" => "secret"
  }

  setup do
    saved = Map.new(@variables, &{&1, System.get_env(&1)})
    Enum.each(@variables, &System.delete_env/1)

    on_exit(fn ->
      Enum.each(saved, fn
        {name, nil} -> System.delete_env(name)
        {name, value} -> System.put_env(name, value)
      end)
    end)
  end

  defp voice_mode(env, config_env \\ :dev) do
    System.put_env(env)

    @runtime_config
    |> Config.Reader.read!(env: config_env, target: :host)
    |> get_in([:backend, :voice_mode])
  end

  test "an explicit VOICE_MODE wins" do
    assert voice_mode(%{"VOICE_MODE" => "realtime"}) == "realtime"
    assert voice_mode(%{"VOICE_MODE" => " OFF "}) == "off"
    assert voice_mode(Map.put(@livekit, "VOICE_MODE", "turn")) == "turn"
  end

  test "defaults to turn when LiveKit is not fully configured" do
    assert voice_mode(%{}) == "turn"
    assert voice_mode(Map.delete(@livekit, "LIVEKIT_API_SECRET")) == "turn"
  end

  test "defaults to realtime when LiveKit is configured" do
    assert voice_mode(@livekit) == "realtime"
  end

  test "an unknown VOICE_MODE falls back to the default" do
    assert voice_mode(%{"VOICE_MODE" => "loud"}) == "turn"
    assert voice_mode(Map.put(@livekit, "VOICE_MODE", "loud")) == "realtime"
  end

  test "the test environment keeps the compiled default" do
    assert voice_mode(Map.put(@livekit, "VOICE_MODE", "realtime"), :test) == nil
  end
end
