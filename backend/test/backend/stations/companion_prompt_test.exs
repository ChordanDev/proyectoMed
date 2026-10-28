defmodule Backend.Stations.CompanionPromptTest do
  @moduledoc """
  Issue #341: a station with a companion. The generator marks each reply
  `[PACIENTE]`, `[ACOMPANHANTE]` or `[EXAMINADOR]`, and each actor answers with
  its own profile and facts. A station without a companion keeps today's prompt
  and markers.
  """
  use ExUnit.Case, async: true

  alias Backend.Stations
  alias Backend.Stations.StationAI
  alias Backend.Stations.StationAI.Addressee

  @companion_case Path.expand("fixtures/case_format/companion.md", __DIR__)
  @reference_case Path.expand("../../../priv/stations/acute-appendicitis/case.md", __DIR__)

  defp parse!(path) do
    {:ok, package} = path |> File.read!() |> Stations.parse_case()
    package
  end

  describe "the addressee marker" do
    test "[ACOMPANHANTE] is the companion when the station has one" do
      assert {:companion, :marker, "A febre começou há dois dias."} =
               Addressee.split("[ACOMPANHANTE] A febre começou há dois dias.", companion: true)

      assert {:decided, :companion, :marker, "Oi"} =
               Addressee.prefix(" [ acompanhante ] Oi", companion: true)
    end

    test "[ACOMPANHANTE] is an unknown marker without a companion, as before #341" do
      text = "[ACOMPANHANTE] A febre começou há dois dias."
      assert {:patient, :missing_marker, ^text} = Addressee.split(text)
      assert {:patient, :missing_marker, ^text} = Addressee.split(text, companion: false)
    end

    test "a streamed companion reply hands its text on after the decision" do
      test_pid = self()

      {filter, finish} =
        Addressee.stream(
          &send(test_pid, {:text, &1}),
          &send(test_pid, {:decision, &1, &2}),
          companion: true
        )

      filter.("[ACOMPAN")
      refute_received {:decision, _, _}
      filter.("HANTE] Começou ")
      filter.("ontem.")

      assert :companion = finish.()
      assert_received {:decision, :companion, :marker}
      assert_received {:text, "Começou "}
      assert_received {:text, "ontem."}
    end

    test "the patient and examiner markers read as before with a companion" do
      assert {:patient, :marker, "Oi"} = Addressee.split("[PACIENTE] Oi", companion: true)
      assert {:examiner, :marker, ""} = Addressee.split("[EXAMINADOR]", companion: true)
    end
  end

  describe "the prompt of a station with a companion" do
    setup do
      %{prompt: StationAI.system_prompt(parse!(@companion_case))}
    end

    test "describes the companion with its own profile", %{prompt: prompt} do
      assert prompt =~ "PERFIL DO ACOMPANHANTE"
      assert prompt =~ "- Nome: Juliana Souza"
      assert prompt =~ "- Persona: Mãe de Lucas, preocupada e colaborativa."
      assert prompt =~ "- Idade: 34"
      assert prompt =~ "- Tom: Fala de forma direta, com vocabulário simples."
      assert prompt =~ "PERFIL DO PACIENTE"
      assert prompt =~ "- Nome: Lucas Souza"
    end

    test "lists each actor's facts under that actor", %{prompt: prompt} do
      [_before, patient_facts] =
        String.split(prompt, "FATOS QUE O PACIENTE PODE REVELAR", parts: 2)

      [patient_facts, companion_facts] =
        String.split(patient_facts, "FATOS QUE O ACOMPANHANTE PODE REVELAR", parts: 2)

      [companion_facts, _rest] = String.split(companion_facts, "\n\n", parts: 2)

      assert patient_facts =~ "(choro)"
      refute patient_facts =~ "(febre-inicio)"
      assert companion_facts =~ "(febre-inicio)"
      assert companion_facts =~ "(febre-maxima)"
      assert companion_facts =~ "(duvida-mae-01)"
      refute companion_facts =~ "(choro)"
    end

    test "answers the current state, a fact in other words and numbers as the patient prompt does",
         %{prompt: prompt} do
      single = StationAI.system_prompt(parse!(@reference_case))

      for rule <- [
            "Uma pergunta sobre como algo está agora pede só o estado atual:",
            ~s(Por exemplo, se a dor mudou de lugar, "Onde dói?" e "Onde é a dor?" perguntam onde ela dói agora),
            "Se um fato da lista responde à pergunta, mesmo com outras palavras",
            "Diga números, escalas e medidas de um fato só quando a pergunta pedir o número;",
            "Por exemplo, se perguntarem se a dor é forte, diga que é bem forte;"
          ] do
        assert single =~ rule
        assert prompt =~ rule
      end
    end

    test "personal data outside each profile, the context and the list gets only the refusal",
         %{prompt: prompt} do
      assert prompt =~
               ~s(Qualquer outro dado pessoal de quem fala que não esteja no seu perfil, no Contexto nem na sua lista, como de onde é, onde nasceu, a sua família ou os seus gostos, também está fora da lista: responda só "Não consta no script.", sem inventar uma resposta antes dela.)
    end

    test "lets the patient give only the chief complaint to an open question", %{prompt: prompt} do
      assert prompt =~
               "Quando o estudante perguntar ao paciente o que ele sente, o que o traz à consulta ou como ele está, o paciente diz só o motivo da consulta que aparece no Contexto, em uma frase simples, sem dizer há quanto tempo começou, onde exatamente é, quão forte é nem o que mais ele sente: cada um desses detalhes é um fato que o estudante precisa perguntar."
    end

    test "asks for one of the three markers", %{prompt: prompt} do
      assert prompt =~ "[PACIENTE], [ACOMPANHANTE], [EXAMINADOR:EXAME] ou [EXAMINADOR]"
      assert prompt =~ "Use [EXAMINADOR:EXAME]"
      assert prompt =~ "Use [ACOMPANHANTE]"
    end
  end

  describe "the per-turn part in the final minutes" do
    test "asks for the pending mandatory questions with their speaker's marker" do
      package = parse!(@companion_case)
      question = %{id: "duvida-mae-01", speaker: :companion, content: "“Quando volto?”"}

      {stable, per_turn} =
        StationAI.system_prompt_parts(package, %{mandatory_questions: [question]})

      assert stable == StationAI.system_prompt(package)
      assert per_turn =~ "PERGUNTAS OBRIGATÓRIAS DOS MINUTOS FINAIS"
      assert per_turn =~ "  - [ACOMPANHANTE] (duvida-mae-01) “Quando volto?”"
      assert {_stable, ""} = StationAI.system_prompt_parts(package, %{})
    end
  end

  describe "a station without a companion" do
    test "keeps the prompt it had without actors" do
      package = parse!(@reference_case)
      prompt = StationAI.system_prompt(package)

      assert prompt == StationAI.system_prompt(Map.delete(package, "actors"))
      refute prompt =~ "ACOMPANHANTE"
      assert prompt =~ "[PACIENTE], [EXAMINADOR:EXAME] ou [EXAMINADOR]"
    end
  end
end
