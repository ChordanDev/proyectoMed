defmodule Backend.Stations.PreStationNotice do
  @moduledoc """
  The Pre-Station Notice (ADR-003 #36, ADR-013 amendment on #209, issue #334):
  the pt-BR educational notice plus every active provider and its role.

  Providers are derived from the running configuration (the adapter each seam
  resolves, the voice mode and the voice provider), so the notice lists
  exactly what a station calls: a disabled seam names no provider. Each role
  says whether the provider processes `text` or `audio`; a provider
  `processes` `audio` when any of its roles does.
  """

  @providers [
    {"anthropic", "Anthropic (Claude)"},
    {"openai", "OpenAI"},
    {"typesafe", "TypeSafe (Jev)"},
    {"livekit", "LiveKit"},
    {"deepgram", "Deepgram"},
    {"elevenlabs", "ElevenLabs"}
  ]

  @roles %{
    "simulated_patient" =>
      {"text", "Gera as falas do paciente simulado a partir do texto da conversa."},
    "patient_adjudicator" =>
      {"text", "Revisa respostas do paciente quando a verificação automática fica indecisa."},
    "jev_verification" =>
      {"text", "Verifica as respostas do paciente e classifica as evidências da avaliação."},
    "rubric_resolver" =>
      {"text", "Decide itens do checklist que a verificação automática deixou indecisos."},
    "learner_feedback" => {"text", "Escreve as recomendações do resultado educacional."},
    "audio_transport" => {"audio", "Transmite o áudio da conversa em tempo real."},
    "speech_to_text" => {"audio", "Transcreve a sua fala."},
    "text_to_speech" => {"audio", "Gera a voz do paciente a partir do texto aprovado."}
  }

  @spec build() :: map()
  def build do
    %{
      "title" => "Ferramenta Educacional",
      "body" =>
        "Ferramenta educacional independente para treino de habilidades clínicas. " <>
          "Não insira dados de pacientes reais.",
      "educational_disclaimer" =>
        "Estimativa educacional gerada por IA. Não é nota oficial do Revalida. Não indica " <>
          "aprovação, reprovação, certificação ou prontidão para o exame.",
      "audio_consent" =>
        "Ao ativar a voz, você aceita que o áudio da conversa seja processado pelos " <>
          "provedores de áudio listados. Sem a voz, a estação funciona por texto.",
      "providers" => providers()
    }
  end

  defp providers do
    active = text_roles() ++ audio_roles()

    for {id, name} <- @providers,
        roles = for({^id, role} <- active, do: role),
        roles != [] do
      %{
        "id" => id,
        "name" => name,
        "processes" =>
          if(Enum.any?(roles, &(&1["processes"] == "audio")), do: "audio", else: "text"),
        "roles" => roles
      }
    end
  end

  defp text_roles do
    [
      {"simulated_patient", station_ai_provider()},
      {"patient_adjudicator", provider_of(:patient_adjudicator_adapter)},
      {"jev_verification", jev_provider()},
      {"rubric_resolver", provider_of(:rubric_resolver_adapter)},
      {"learner_feedback", provider_of(:learner_feedback_adapter)}
    ]
    |> Enum.flat_map(fn
      {_role, nil} -> []
      {role, provider} -> [{provider, role(role)}]
    end)
  end

  defp audio_roles do
    case Application.get_env(:backend, :voice_mode, "turn") do
      "realtime" ->
        [
          {"livekit", role("audio_transport")},
          {"deepgram", role("speech_to_text")},
          {"elevenlabs", role("text_to_speech")}
        ]

      "turn" ->
        turn_audio_roles(Application.get_env(:backend, :voice_provider, :openai))

      _off ->
        []
    end
  end

  defp turn_audio_roles(:deepgram_elevenlabs) do
    [{"deepgram", role("speech_to_text")}, {"elevenlabs", role("text_to_speech")}]
  end

  # The OpenAI voice path is unavailable without its key.
  defp turn_audio_roles(_openai) do
    case Application.get_env(:backend, :openai_api_key) do
      key when is_binary(key) and key != "" ->
        [{"openai", role("speech_to_text")}, {"openai", role("text_to_speech")}]

      _missing ->
        []
    end
  end

  defp role(id) do
    {processes, description} = Map.fetch!(@roles, id)
    %{"id" => id, "processes" => processes, "description" => description}
  end

  # The Station AI defaults to OpenAI, as `Backend.Stations` resolves it.
  defp station_ai_provider do
    :backend
    |> Application.get_env(:station_ai_adapter, Backend.Stations.StationAI.OpenAIAdapter)
    |> vendor()
  end

  defp jev_provider do
    if Application.get_env(:backend, :jev_decision_adapter) ==
         Backend.Stations.JevDecision.TypesafeAdapter,
       do: "typesafe"
  end

  defp provider_of(key), do: :backend |> Application.get_env(key) |> vendor()

  defp vendor(adapter) when is_atom(adapter) and not is_nil(adapter) do
    case adapter |> Atom.to_string() |> String.split(".") |> List.last() do
      "AnthropicAdapter" -> "anthropic"
      "OpenAIAdapter" -> "openai"
      _disabled_or_test_double -> nil
    end
  end

  defp vendor(_adapter), do: nil
end
