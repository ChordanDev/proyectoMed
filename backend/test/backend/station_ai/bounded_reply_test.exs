defmodule Backend.StationAI.BoundedReplyTest do
  use ExUnit.Case, async: true

  alias Backend.StationAI
  alias Backend.StationAI.BoundedReply

  describe "bound/2 malformed inputs" do
    test "nil is replaced with the canonical refusal" do
      assert BoundedReply.bound(nil, package_with([])) == StationAI.refusal_text()
    end

    test "an empty string is replaced with the canonical refusal" do
      assert BoundedReply.bound("", package_with([])) == StationAI.refusal_text()
    end

    test "whitespace-only text is replaced with the canonical refusal" do
      assert BoundedReply.bound("   \n\t  ", package_with([])) == StationAI.refusal_text()
    end

    test "an integer is replaced with the canonical refusal" do
      assert BoundedReply.bound(123, package_with([])) == StationAI.refusal_text()
    end

    test "a map is replaced with the canonical refusal" do
      assert BoundedReply.bound(%{}, package_with([])) == StationAI.refusal_text()
    end

    test "an atom is replaced with the canonical refusal" do
      assert BoundedReply.bound(:hello, package_with([])) == StationAI.refusal_text()
    end

    test "text longer than 2000 chars is replaced with the canonical refusal" do
      long_text = String.duplicate("a", 5000)

      assert BoundedReply.bound(long_text, package_with([])) == StationAI.refusal_text()
    end
  end

  describe "bound/2 out-of-scope roleplay leakage" do
    @leakage_texts [
      "Sou uma inteligência artificial.",
      "Sou um modelo de linguagem.",
      "Como IA, não posso ajudar.",
      "Sou uma IA.",
      "I am an AI assistant.",
      "I am a language model.",
      "Sure, I'd be happy to help.",
      "Certainly, I can do that."
    ]

    for text <- @leakage_texts do
      test "replaces #{inspect(text)} with the canonical refusal" do
        assert BoundedReply.bound(unquote(text), package_with([])) == StationAI.refusal_text()
      end
    end
  end

  describe "bound/2 language containment" do
    test "an English reply with multiple markers is replaced with the canonical refusal" do
      text = "Yes, the pain started this morning."

      assert BoundedReply.bound(text, package_with([])) == StationAI.refusal_text()
    end

    test "a short English reply with only the pronoun is replaced with the canonical refusal" do
      text = "No, I don't think so."

      assert BoundedReply.bound(text, package_with([])) == StationAI.refusal_text()
    end

    test "a pt-BR reply is left unchanged" do
      text = "Sim, a dor começou de manhã."

      assert BoundedReply.bound(text, package_with([])) == text
    end

    test "a pt-BR reply without diacritics is left unchanged" do
      text = "A dor começou durante uma caminhada."

      assert BoundedReply.bound(text, package_with([])) == text
    end
  end

  describe "bound/2 allowed text" do
    test "a coherent pt-BR reply is left unchanged" do
      text = "A dor começou durante uma caminhada."

      assert BoundedReply.bound(text, package_with([])) == text
    end

    test "the canonical refusal text is always allowed through verbatim" do
      assert BoundedReply.bound(StationAI.refusal_text(), package_with([])) ==
               StationAI.refusal_text()
    end
  end

  describe "bound/2 response_rules enforcement" do
    test "polite rule rejects an insult" do
      rules = [%{"id" => "polite", "instruction" => "stay polite"}]

      assert BoundedReply.bound("Você é um idiota.", package_with(rules)) ==
               StationAI.refusal_text()
    end

    test "polite rule leaves a non-insulting reply unchanged" do
      rules = [%{"id" => "polite", "instruction" => "stay polite"}]

      assert BoundedReply.bound("Você é um médico excelente.", package_with(rules)) ==
               "Você é um médico excelente."
    end

    test "length-cap rule rejects text longer than max_length" do
      rules = [%{"id" => "length-cap", "max_length" => 200}]
      text = String.duplicate("a", 300)

      assert BoundedReply.bound(text, package_with(rules)) == StationAI.refusal_text()
    end

    test "length-cap rule leaves shorter text unchanged" do
      rules = [%{"id" => "length-cap", "max_length" => 200}]
      text = String.duplicate("a", 30)

      assert BoundedReply.bound(text, package_with(rules)) == text
    end

    test "max-length alias rule rejects text longer than max_length" do
      rules = [%{"id" => "max-length", "max_length" => 100}]
      text = String.duplicate("a", 200)

      assert BoundedReply.bound(text, package_with(rules)) == StationAI.refusal_text()
    end

    test "unknown rule ids are ignored and text is left unchanged" do
      rules = [%{"id" => "unknown-fact", "instruction" => "Do not invent facts."}]
      text = "A dor começou durante uma caminhada."

      assert BoundedReply.bound(text, package_with(rules)) == text
    end
  end

  defp package_with(rules) do
    %{
      "language" => "pt-BR",
      "response_rules" => rules,
      "revealable_facts" => []
    }
  end
end
