defmodule Backend.ArchitectureTest do
  @moduledoc """
  Architecture boundary tests enforcing ADR-007:
    - BackendWeb must only interact with the domain through Backend.Stations.
    - BackendWeb must never call internal implementation modules directly.
    - Dependencies flow unidirectionally from web to domain.
  """

  use ExUnit.Case, async: true

  @forbidden_modules [
    Backend.Conversation,
    Backend.Stations.Conversation,
    Backend.StationLoader,
    Backend.Stations.StationLoader,
    Backend.StationAI,
    Backend.Stations.StationAI,
    Backend.Stations.StationAI.BoundedReply,
    Backend.Stations.StationAI.OpenAIAdapter,
    Backend.Stations.StationAI.NoOpAdapter,
    Backend.Evaluator,
    Backend.Stations.Evaluator,
    Backend.Transcription,
    Backend.Stations.Transcription,
    Backend.TTS,
    Backend.Stations.TTS,
    Backend.StationPackage,
    Backend.Stations.StationPackage,
    Backend.Stations.LiveKit,
    Backend.Stations.MediaSession
  ]

  @web_dir Path.expand("../../lib/backend_web", __DIR__)
  @internal_dir Path.expand("../../lib/backend/stations", __DIR__)

  test "BackendWeb never references internal domain implementation modules directly" do
    web_files = Path.wildcard(Path.join(@web_dir, "**/*.ex"))
    assert web_files != [], "Expected to find files in #{@web_dir}"

    violations =
      for file <- web_files,
          forbidden <- @forbidden_modules,
          referenced?(file, forbidden) do
        {Path.relative_to(file, File.cwd!()), forbidden}
      end

    assert violations == [],
           """
           Architecture violation detected!
           BackendWeb must only call the public Backend.Stations context interface.
           Direct calls to internal implementation modules are forbidden:
           #{inspect(violations, pretty: true)}
           """
  end

  test "BackendWeb controllers only call Backend.Stations for domain logic" do
    station_controllers = [
      "lib/backend_web/controllers/station_controller.ex",
      "lib/backend_web/controllers/transcription_controller.ex",
      "lib/backend_web/controllers/tts_controller.ex",
      "lib/backend_web/controllers/voice_session_controller.ex"
    ]

    for rel_path <- station_controllers do
      full_path = Path.expand("../../" <> rel_path, __DIR__)
      assert File.exists?(full_path), "Expected #{rel_path} to exist"

      assert referenced?(full_path, Backend.Stations),
             "Expected #{rel_path} to reference the public Backend.Stations context"
    end
  end

  test "internal stations modules never depend on BackendWeb" do
    internal_files = Path.wildcard(Path.join(@internal_dir, "**/*.ex"))
    assert internal_files != [], "Expected to find files in #{@internal_dir}"

    violations =
      for file <- internal_files,
          referenced?(file, BackendWeb) do
        {Path.relative_to(file, File.cwd!()), BackendWeb}
      end

    assert violations == [],
           """
           Architecture violation detected!
           Internal domain modules must not depend on BackendWeb:
           #{inspect(violations, pretty: true)}
           """
  end

  defp referenced?(file_path, target_module) do
    content = File.read!(file_path)
    target_str = Atom.to_string(target_module) |> String.trim_leading("Elixir.")

    # Match aliases, function calls, and module references
    pattern = ~r/\b#{Regex.escape(target_str)}\b/
    Regex.match?(pattern, content)
  end
end
