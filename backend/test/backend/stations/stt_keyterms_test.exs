defmodule Backend.Stations.SttKeytermsTest do
  use ExUnit.Case, async: true

  alias Backend.Stations.SttKeyterms

  @appendicitis Path.expand("../../../priv/stations/acute-appendicitis/package.json", __DIR__)
  @chest_pain Path.expand(
                "../../../priv/stations/chest-pain-initial-assessment/package.json",
                __DIR__
              )

  defp load(path), do: path |> File.read!() |> Jason.decode!()

  describe "for_package/1 on acute-appendicitis (no stt_keyterms authored)" do
    setup do
      package = load(@appendicitis)
      refute Map.has_key?(package, "stt_keyterms")
      %{keyterms: SttKeyterms.for_package(package)}
    end

    test "derives the rehearsal-critical clinical vocabulary", %{keyterms: keyterms} do
      for term <- ["McBurney", "Blumberg", "Rovsing", "palpação", "fossa ilíaca direita"] do
        assert term in keyterms, "expected #{inspect(term)} in #{inspect(keyterms)}"
      end
    end

    test "includes impresso keywords", %{keyterms: keyterms} do
      assert "hemograma" in keyterms
    end

    test "respects the term cap and the estimated token budget", %{keyterms: keyterms} do
      assert length(keyterms) <= SttKeyterms.max_terms()
      assert SttKeyterms.estimated_tokens(keyterms) <= SttKeyterms.token_budget()
    end

    test "is deduplicated case-insensitively", %{keyterms: keyterms} do
      downcased = Enum.map(keyterms, &String.downcase/1)
      assert downcased == Enum.uniq(downcased)
    end

    test "is deterministic" do
      package = load(@appendicitis)
      assert SttKeyterms.for_package(package) == SttKeyterms.for_package(package)
    end
  end

  describe "for_package/1 with explicit stt_keyterms" do
    test "keeps every authored term first, in order" do
      package = load(@chest_pain)
      explicit = package["stt_keyterms"]
      keyterms = SttKeyterms.for_package(package)

      assert Enum.take(keyterms, length(explicit)) == explicit
      assert length(keyterms) > length(explicit)
    end

    test "drops non-string and blank authored terms and dedupes against derived ones" do
      package = %{
        "stt_keyterms" => ["Palpação", 42, "  ", nil, "McBurney"],
        "impressos" => [%{"keywords" => ["palpação", "mcburney", "hemograma"]}],
        "revealable_facts" => [%{"content" => "Dor no ponto de McBurney."}]
      }

      assert SttKeyterms.for_package(package) == ["Palpação", "McBurney", "hemograma"]
    end
  end

  describe "for_package/1 derivation sources" do
    test "extracts eponyms named after clinical anchor nouns anywhere in the package" do
      package = %{
        "rubric" => [%{"description" => "Pesquisa o sinal de Murphy e a manobra de Giordano."}],
        "revealable_facts" => [
          %{"content" => "Sinal do piparote negativo. Escala de Glasgow 15."}
        ]
      }

      keyterms = SttKeyterms.for_package(package)
      assert "Murphy" in keyterms
      assert "Giordano" in keyterms
      assert "Glasgow" in keyterms
      refute "piparote" in keyterms
    end

    test "includes shared lexicon terms only when the package text mentions them" do
      package = %{"revealable_facts" => [%{"content" => "Descompressão brusca dolorosa."}]}
      keyterms = SttKeyterms.for_package(package)

      assert "descompressão brusca" in keyterms
      refute "troponina" in keyterms
    end

    test "matches lexicon terms case-insensitively, keeping the lexicon spelling" do
      package = %{"revealable_facts" => [%{"content" => "PROTEÍNA C REATIVA elevada."}]}
      assert "proteína C reativa" in SttKeyterms.for_package(package)
    end

    test "matches lexicon terms on whole words only" do
      package = %{"revealable_facts" => [%{"content" => "Hiperfebre relatada."}]}
      refute "febre" in SttKeyterms.for_package(package)
    end

    test "an empty package yields no keyterms" do
      assert SttKeyterms.for_package(%{}) == []
    end
  end

  describe "cap" do
    test "keeps at most max_terms, preferring explicit terms" do
      explicit = for i <- 1..80, do: "termo#{i}"
      keyterms = SttKeyterms.for_package(%{"stt_keyterms" => explicit})

      assert keyterms == Enum.take(explicit, SttKeyterms.max_terms())
    end

    test "stops before the estimated token budget is exceeded" do
      long = for i <- 1..40, do: String.duplicate("x", 40) <> "#{i}"
      keyterms = SttKeyterms.for_package(%{"stt_keyterms" => long})

      assert SttKeyterms.estimated_tokens(keyterms) <= SttKeyterms.token_budget()
      assert length(keyterms) < 40
      assert keyterms == Enum.take(long, length(keyterms))
    end
  end
end
