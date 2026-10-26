defmodule Backend.Stations.PreStationNoticeTest do
  @moduledoc """
  The Pre-Station Notice names every active provider and its role (ADR-003
  #36, ADR-013 amendment on #209, issue #334), derived from the running
  configuration so it never drifts from what the station actually calls.
  """

  # Edits application env: not async.
  use ExUnit.Case, async: false

  alias Backend.Stations

  @keys [
    :station_ai_adapter,
    :rubric_resolver_adapter,
    :learner_feedback_adapter,
    :patient_adjudicator_adapter,
    :jev_decision_adapter,
    :voice_mode,
    :voice_provider,
    :openai_api_key
  ]

  setup do
    previous = for key <- @keys, do: {key, Application.fetch_env(:backend, key)}

    on_exit(fn ->
      for {key, value} <- previous do
        case value do
          {:ok, value} -> Application.put_env(:backend, key, value)
          :error -> Application.delete_env(:backend, key)
        end
      end
    end)

    :ok
  end

  defp configure(env) do
    for key <- @keys, do: Application.delete_env(:backend, key)
    for {key, value} <- env, do: Application.put_env(:backend, key, value)
  end

  defp providers, do: Stations.pre_station_notice()["providers"]

  defp roles_by_provider do
    Map.new(providers(), fn provider ->
      {provider["id"], Enum.map(provider["roles"], & &1["id"])}
    end)
  end

  test "Claude with Jev and the realtime voice path names every provider and role" do
    configure(
      station_ai_adapter: Backend.Stations.StationAI.AnthropicAdapter,
      rubric_resolver_adapter: Backend.Stations.RubricAssessment.Resolver.AnthropicAdapter,
      learner_feedback_adapter: Backend.Stations.LearnerFeedback.AnthropicAdapter,
      patient_adjudicator_adapter: Backend.Stations.PatientAdjudicator.AnthropicAdapter,
      jev_decision_adapter: Backend.Stations.JevDecision.TypesafeAdapter,
      voice_mode: "realtime"
    )

    assert roles_by_provider() == %{
             "anthropic" => [
               "simulated_patient",
               "patient_adjudicator",
               "rubric_resolver",
               "learner_feedback"
             ],
             "typesafe" => ["jev_verification"],
             "livekit" => ["audio_transport"],
             "deepgram" => ["speech_to_text"],
             "cartesia" => ["text_to_speech"]
           }

    assert Enum.map(providers(), & &1["processes"]) == ["text", "text", "audio", "audio", "audio"]

    names = Map.new(providers(), &{&1["id"], &1["name"]})
    assert names["deepgram"] == "Deepgram"
    assert names["cartesia"] == "Cartesia"
  end

  test "OpenAI with the turn-based OpenAI voice names OpenAI for text and audio" do
    configure(
      station_ai_adapter: Backend.Stations.StationAI.OpenAIAdapter,
      rubric_resolver_adapter: Backend.Stations.RubricAssessment.Resolver.OpenAIAdapter,
      learner_feedback_adapter: Backend.Stations.LearnerFeedback.OpenAIAdapter,
      voice_mode: "turn",
      openai_api_key: "sk-test"
    )

    assert [%{"id" => "openai", "name" => "OpenAI", "processes" => "audio", "roles" => roles}] =
             providers()

    assert Enum.map(roles, &{&1["id"], &1["processes"]}) == [
             {"simulated_patient", "text"},
             {"rubric_resolver", "text"},
             {"learner_feedback", "text"},
             {"speech_to_text", "audio"},
             {"text_to_speech", "audio"}
           ]
  end

  test "the turn-based Deepgram and Cartesia voice names both audio providers" do
    configure(
      station_ai_adapter: Backend.Stations.StationAI.OpenAIAdapter,
      voice_mode: "turn",
      voice_provider: :deepgram_cartesia
    )

    assert roles_by_provider() == %{
             "openai" => ["simulated_patient"],
             "deepgram" => ["speech_to_text"],
             "cartesia" => ["text_to_speech"]
           }
  end

  test "disabled seams and voice off name no provider for them" do
    configure(
      station_ai_adapter: Backend.Stations.StationAI.AnthropicAdapter,
      rubric_resolver_adapter: Backend.Stations.RubricAssessment.Resolver.DisabledAdapter,
      learner_feedback_adapter: Backend.Stations.LearnerFeedback.DisabledAdapter,
      patient_adjudicator_adapter: Backend.Stations.PatientAdjudicator.DisabledAdapter,
      jev_decision_adapter: Backend.Stations.JevDecision.DisabledAdapter,
      voice_mode: "off",
      voice_provider: :deepgram_cartesia
    )

    assert roles_by_provider() == %{"anthropic" => ["simulated_patient"]}
  end

  test "turn-based OpenAI voice without a key is not an active provider" do
    configure(station_ai_adapter: Backend.Stations.StationAI.NoOpAdapter, voice_mode: "turn")

    assert providers() == []
  end

  test "carries the pt-BR notice and a description for every role" do
    configure(
      station_ai_adapter: Backend.Stations.StationAI.AnthropicAdapter,
      voice_mode: "realtime"
    )

    notice = Stations.pre_station_notice()

    assert notice["title"] == "Ferramenta Educacional"
    assert notice["body"] =~ "Não insira dados de pacientes reais"
    assert notice["educational_disclaimer"] =~ "Não é nota oficial do Revalida"
    assert notice["audio_consent"] =~ "áudio"

    for provider <- notice["providers"], role <- provider["roles"] do
      assert is_binary(provider["name"]) and provider["name"] != ""
      assert is_binary(role["description"]) and role["description"] != ""
    end
  end
end
