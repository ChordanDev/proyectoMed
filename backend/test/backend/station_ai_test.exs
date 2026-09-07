defmodule Backend.StationAITest do
  use ExUnit.Case, async: false

  alias Backend.StationAI

  @fixtures_path Path.expand("../../priv/stations/fixtures", __DIR__)

  setup do
    Backend.StationAITest.CaptureAdapter.reset()

    previous_adapter = Application.get_env(:backend, :station_ai_adapter)
    previous_refusal = Application.get_env(:backend, :station_ai_refusal_text)

    Application.put_env(:backend, :station_ai_adapter, Backend.StationAITest.CaptureAdapter)

    on_exit(fn ->
      restore_env(:station_ai_adapter, previous_adapter)
      restore_env(:station_ai_refusal_text, previous_refusal)
    end)

    :ok
  end

  describe "next_reply/2 boundary" do
    test "passes the active Station Package to the adapter unchanged" do
      package = load_fixture("valid-package.json")
      context = %{conversation: [], language: "pt-BR"}

      assert {:ok, reply} = StationAI.next_reply(package, context)

      assert is_binary(reply.text)
      assert is_list(reply.used_facts)
      assert Backend.StationAITest.CaptureAdapter.last_package() == package
    end

    test "passes the conversation context to the adapter unchanged" do
      package = load_fixture("valid-package.json")

      context = %{
        conversation: [
          %{role: :student, text: "Quando começou a dor?"},
          %{role: :patient, text: "Há duas horas."}
        ],
        language: "pt-BR"
      }

      StationAI.next_reply(package, context)

      assert Backend.StationAITest.CaptureAdapter.last_context() == context
    end

    test "returns only text and used_facts, the fields the conversation flow consumes" do
      package = load_fixture("valid-package.json")
      context = %{conversation: [], language: "pt-BR"}

      assert {:ok, reply} = StationAI.next_reply(package, context)

      assert Map.keys(reply) |> Enum.sort() == [:text, :used_facts]
    end

    test "annotates the reply with the used_facts surfaced in the adapter text" do
      package = load_fixture("valid-package.json")
      context = %{conversation: [], language: "pt-BR"}

      assert {:ok, %{used_facts: used_facts}} = StationAI.next_reply(package, context)

      assert [%{"topic" => "onset"}] = used_facts
    end

    test "preserves used_facts supplied by the adapter verbatim" do
      Application.put_env(
        :backend,
        :station_ai_adapter,
        Backend.StationAITest.AdapterSuppliesFacts
      )

      package = load_fixture("valid-package.json")
      context = %{conversation: [], language: "pt-BR"}

      assert {:ok, %{used_facts: used_facts}} = StationAI.next_reply(package, context)

      assert used_facts == [%{"topic" => "supplied", "content" => "by adapter"}]
    end

    test "returns an empty used_facts list when no fact is referenced in the reply" do
      Application.put_env(:backend, :station_ai_adapter, Backend.StationAITest.EmptyReplyAdapter)

      package = load_fixture("valid-package.json")
      context = %{conversation: [], language: "pt-BR"}
      refusal = StationAI.refusal_text()

      assert {:ok, %{text: ^refusal, used_facts: []}} =
               StationAI.next_reply(package, context)
    end

    test "propagates adapter errors without mutating them" do
      Application.put_env(:backend, :station_ai_adapter, Backend.StationAITest.ErrorAdapter)

      package = load_fixture("valid-package.json")
      context = %{conversation: [], language: "pt-BR"}

      assert StationAI.next_reply(package, context) == {:error, :provider_down}
    end
  end

  describe "next_reply/2 bounded policy" do
    test "replaces adapter roleplay leakage with the canonical refusal" do
      Application.put_env(
        :backend,
        :station_ai_adapter,
        Backend.StationAITest.RoleplayLeakAdapter
      )

      package = load_fixture("valid-package.json")
      context = %{conversation: [], language: "pt-BR"}

      assert {:ok, %{text: refusal_text, used_facts: []}} =
               StationAI.next_reply(package, context)

      assert refusal_text == StationAI.refusal_text()
    end

    test "replaces malformed adapter output with the canonical refusal" do
      Application.put_env(:backend, :station_ai_adapter, Backend.StationAITest.MalformedAdapter)

      package = load_fixture("valid-package.json")
      context = %{conversation: [], language: "pt-BR"}

      assert {:ok, %{text: refusal_text, used_facts: []}} =
               StationAI.next_reply(package, context)

      assert refusal_text == StationAI.refusal_text()
    end

    test "keeps coherent pt-BR adapter output and computes used_facts" do
      package = load_fixture("valid-package.json")
      context = %{conversation: [], language: "pt-BR"}

      assert {:ok, reply} = StationAI.next_reply(package, context)

      assert reply.text == "A dor começou durante uma caminhada."
      assert [%{"topic" => "onset"}] = reply.used_facts
    end
  end

  describe "system_prompt/1 boundary" do
    test "embeds the patient profile, revealable facts, and response rules" do
      package = load_fixture("valid-package.json")
      prompt = StationAI.system_prompt(package)

      assert prompt =~ package["patient_profile"]["persona"]
      assert prompt =~ package["patient_profile"]["tone"]
      assert prompt =~ "caminhada"
      assert prompt =~ "Do not invent facts absent from this package"
      assert prompt =~ "pt-BR"
    end

    test "marks the canonical pt-BR refusal text as the out-of-scope response" do
      package = load_fixture("valid-package.json")
      prompt = StationAI.system_prompt(package)

      assert prompt =~ ~s("Não tenho essa informação")
    end

    test "lists every response rule id so adapters can apply each one" do
      package = load_fixture("valid-package.json")
      prompt = StationAI.system_prompt(package)

      for %{"id" => id} <- package["response_rules"] do
        assert prompt =~ "[#{id}]"
      end
    end
  end

  describe "detect_used_facts/2" do
    setup do
      [
        facts: [
          %{"topic" => "onset", "content" => "A dor começou durante uma caminhada"},
          %{"topic" => "alergia", "content" => "Alergia a penicilina"}
        ]
      ]
    end

    test "matches by content substring", %{facts: facts} do
      assert [%{"topic" => "onset"}] =
               StationAI.detect_used_facts(
                 "A dor começou durante uma caminhada mesmo hoje.",
                 facts
               )
    end

    test "matches by topic substring when content is paraphrased", %{facts: facts} do
      assert [%{"topic" => "alergia"}] =
               StationAI.detect_used_facts("Sobre a alergia, sim.", facts)
    end

    test "returns an empty list when no fact is referenced", %{facts: facts} do
      assert [] = StationAI.detect_used_facts("Não tenho essa informação", facts)
    end

    test "ignores facts with empty content and missing topic", %{facts: facts} do
      padded = [%{"topic" => "", "content" => ""} | facts]

      assert StationAI.detect_used_facts(
               "A dor começou durante uma caminhada mesmo hoje.",
               padded
             ) ==
               [%{"topic" => "onset", "content" => "A dor começou durante uma caminhada"}]
    end
  end

  describe "refusal_text/0" do
    test "returns the canonical pt-BR refusal by default" do
      Application.delete_env(:backend, :station_ai_refusal_text)

      assert StationAI.refusal_text() == "Não tenho essa informação"
    end

    test "honors application env override" do
      Application.put_env(:backend, :station_ai_refusal_text, "No sé.")

      assert StationAI.refusal_text() == "No sé."
    end
  end

  defp load_fixture(name) do
    @fixtures_path
    |> Path.join(name)
    |> File.read!()
    |> Jason.decode!()
  end

  defp restore_env(key, value) do
    case value do
      nil -> Application.delete_env(:backend, key)
      v -> Application.put_env(:backend, key, v)
    end
  end

  defmodule CaptureAdapter do
    @moduledoc false
    @behaviour Backend.StationAI

    def reset do
      :persistent_term.put({__MODULE__, :package}, nil)
      :persistent_term.put({__MODULE__, :context}, nil)
    end

    def last_package, do: :persistent_term.get({__MODULE__, :package})
    def last_context, do: :persistent_term.get({__MODULE__, :context})

    @impl true
    def next_reply(package, context) do
      :persistent_term.put({__MODULE__, :package}, package)
      :persistent_term.put({__MODULE__, :context}, context)
      {:ok, %{text: "A dor começou durante uma caminhada."}}
    end
  end

  defmodule EmptyReplyAdapter do
    @moduledoc false
    @behaviour Backend.StationAI

    @impl true
    def next_reply(_package, _context), do: {:ok, %{text: ""}}
  end

  defmodule ErrorAdapter do
    @moduledoc false
    @behaviour Backend.StationAI

    @impl true
    def next_reply(_package, _context), do: {:error, :provider_down}
  end

  defmodule AdapterSuppliesFacts do
    @moduledoc false
    @behaviour Backend.StationAI

    @impl true
    def next_reply(_package, _context) do
      {:ok,
       %{
         text: "anything",
         used_facts: [%{"topic" => "supplied", "content" => "by adapter"}]
       }}
    end
  end

  defmodule RoleplayLeakAdapter do
    @moduledoc false
    @behaviour Backend.StationAI

    @impl true
    def next_reply(_package, _context),
      do: {:ok, %{text: "Sou uma inteligência artificial."}}
  end

  defmodule MalformedAdapter do
    @moduledoc false
    @behaviour Backend.StationAI

    @impl true
    def next_reply(_package, _context), do: {:ok, %{text: ""}}
  end
end
