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
