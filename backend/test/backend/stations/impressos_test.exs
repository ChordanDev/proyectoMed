defmodule Backend.Stations.ImpressosTest do
  use ExUnit.Case, async: true

  alias Backend.Stations.Impressos

  describe "normalize/1" do
    test "downcases and strips accents/combining marks" do
      assert Impressos.normalize("Tomografia de Crânio") == "tomografia de cranio"
      assert Impressos.normalize("ELETROCARDIOGRAMA (ECG)") == "eletrocardiograma (ecg)"
    end
  end

  describe "match/2" do
    @impressos [
      %{"id" => "exame-fisico", "keywords" => ["sinais vitais", "exame físico"]},
      %{"id" => "ecg", "keywords" => ["eletrocardiograma", "ecg"]}
    ]

    test "matches impressos whose keywords are a normalized substring of the text" do
      normalized = Impressos.normalize("quero ver os sinais vitais do paciente")
      assert Impressos.match(@impressos, normalized) == ["exame-fisico"]
    end

    test "matches several impressos in authored order" do
      normalized = Impressos.normalize("quero sinais vitais e o ecg")
      assert Impressos.match(@impressos, normalized) == ["exame-fisico", "ecg"]
    end

    test "returns an empty list when nothing matches" do
      normalized = Impressos.normalize("tomografia de crânio")
      assert Impressos.match(@impressos, normalized) == []
    end

    test "a keyword must start at a word boundary, so abbreviations do not match inside words" do
      impressos = [
        %{"id" => "eas", "keywords" => ["EAS"]},
        %{"id" => "sodio", "keywords" => ["sódio"]},
        %{"id" => "tc", "keywords" => ["TC"]}
      ]

      for text <- ["dor em outras áreas", "um episódio de vômito", "febre, náusea etc"] do
        assert Impressos.match(impressos, Impressos.normalize(text)) == [], text
      end

      assert Impressos.match(impressos, Impressos.normalize("EAS")) == ["eas"]

      assert Impressos.match(impressos, Impressos.normalize("solicito (EAS), sódio e TC")) ==
               ["eas", "sodio", "tc"]
    end

    test "a keyword still matches a longer word it starts, such as a plural" do
      normalized = Impressos.normalize("quero os eletrocardiogramas")
      assert Impressos.match(@impressos, normalized) == ["ecg"]
    end
  end

  # Issue #305: a keyword the learner names only to decline it does not match.
  describe "match/2 with negated mentions" do
    @exams [
      %{"id" => "hemograma", "keywords" => ["hemograma"]},
      %{"id" => "pcr", "keywords" => ["PCR"]},
      %{"id" => "ecg", "keywords" => ["eletrocardiograma", "ECG"]},
      %{"id" => "ultrassonografia", "keywords" => ["ultrassonografia"]},
      %{"id" => "tomografia", "keywords" => ["tomografia"]}
    ]

    defp matched(text), do: Impressos.match(@exams, Impressos.normalize(text))

    test "a negation earlier in the clause does not release, a later clause still does" do
      assert matched("não preciso do ECG, mas solicito hemograma") == ["hemograma"]
    end

    test "a plain request still releases every named exam" do
      assert matched("Solicito hemograma e PCR") == ["hemograma", "pcr"]
    end

    test "sem governs the exam it precedes" do
      assert matched("sem tomografia por enquanto") == []
      assert matched("sem necessidade de tomografia") == []
    end

    test "a trailing não governs the exam that opens its clause" do
      assert matched("solicito ultrassonografia; tomografia não é necessária") ==
               ["ultrassonografia"]

      assert matched("Tomografia não.") == []
    end

    test "nem governs every exam it lists" do
      assert matched("nem hemograma nem PCR") == []
    end

    test "each authored negation cue governs the exam that follows it" do
      for text <- [
            "Não quero hemograma",
            "Dispenso o hemograma",
            "Dispensa hemograma",
            "Não precisa de hemograma",
            "Não vou pedir hemograma",
            "Não vou solicitar hemograma",
            "Não é necessário hemograma",
            "Não é necessária a tomografia"
          ] do
        assert matched(text) == [], text
      end
    end

    test "a connector that starts a new request ends the negated clause" do
      assert matched("Não preciso de ECG e solicito hemograma") == ["hemograma"]
      assert matched("Não preciso de ECG e peço PCR") == ["pcr"]
      assert matched("Sem tomografia porém solicito ultrassonografia") == ["ultrassonografia"]
    end

    test "a negation in an earlier sentence does not govern the next one" do
      assert matched("O paciente não tem febre. Solicito hemograma.") == ["hemograma"]
    end

    test "an exam named both negated and requested is released" do
      assert matched("Não preciso de ECG agora. Solicito ECG depois da dor.") == ["ecg"]
    end
  end

  describe "decide/2" do
    test "no matches is unavailable" do
      assert Impressos.decide([], ["ecg"]) == {:unavailable, []}
    end

    test "all matches already released is already_released" do
      assert Impressos.decide(["ecg"], ["ecg"]) == {:already_released, []}
    end

    test "any new matched id is released, keeping only the new ones in order" do
      assert Impressos.decide(["ecg", "raio-x"], ["ecg"]) == {:released, ["raio-x"]}
      assert Impressos.decide(["raio-x", "ecg"], []) == {:released, ["raio-x", "ecg"]}
    end
  end

  describe "generate_request_id/0" do
    test "returns a unique url-safe string" do
      assert Impressos.generate_request_id() != Impressos.generate_request_id()
      assert String.match?(Impressos.generate_request_id(), ~r/^[A-Za-z0-9_-]+$/)
    end
  end
end
