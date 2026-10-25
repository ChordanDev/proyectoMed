defmodule Backend.Stations.StationAI.AddresseeTest do
  @moduledoc """
  Issue #309: the patient generator starts every reply with `[PACIENTE]` or
  `[EXAMINADOR]`; the marker is parsed in code and never reaches the learner.
  """
  use ExUnit.Case, async: true

  alias Backend.Stations.StationAI.Addressee

  describe "split/1" do
    test "a patient marker is stripped from the reply" do
      assert {:patient, :marker, "Meu nome é Ana."} =
               Addressee.split("[PACIENTE] Meu nome é Ana.")
    end

    test "an examiner marker leaves no text" do
      assert {:examiner, :marker, ""} = Addressee.split("[EXAMINADOR]")
      assert {:examiner, :marker, ""} = Addressee.split("  [EXAMINADOR]\n")
    end

    test "the marker is read without regard to case or inner spaces" do
      assert {:patient, :marker, "Sim."} = Addressee.split("[ paciente ]Sim.")
      assert {:examiner, :marker, ""} = Addressee.split("[Examinador]")
    end

    test "an exam marker is examiner-addressed with source exam_marker and leaves no text (#351)" do
      assert {:examiner, :exam_marker, ""} = Addressee.split("[EXAMINADOR:EXAME]")
      assert {:examiner, :exam_marker, ""} = Addressee.split(" [examinador : exame]\n")

      assert {:examiner, :exam_marker, ""} =
               Addressee.split("[EXAMINADOR:EXAME]", companion: true)
    end

    test "an unknown examiner sub-marker is not a marker and is kept (#351)" do
      assert {:patient, :missing_marker, "[EXAMINADOR:OUTRO] Sim."} =
               Addressee.split("[EXAMINADOR:OUTRO] Sim.")
    end

    test "a missing marker is patient-addressed and keeps the whole text" do
      assert {:patient, :missing_marker, "A dor começou ontem."} =
               Addressee.split("A dor começou ontem.")
    end

    test "an unknown bracket is not a marker and is kept" do
      assert {:patient, :missing_marker, "[sorri] Bom dia."} = Addressee.split("[sorri] Bom dia.")
    end

    test "an empty reply is patient-addressed with a missing marker" do
      assert {:patient, :missing_marker, ""} = Addressee.split("")
    end
  end

  describe "prefix/1 on a streamed reply" do
    test "waits while the marker may still be arriving" do
      assert :undecided = Addressee.prefix("")
      assert :undecided = Addressee.prefix("  ")
      assert :undecided = Addressee.prefix("[PACI")
      assert :undecided = Addressee.prefix("[")
    end

    test "decides as soon as the marker is closed" do
      assert {:decided, :examiner, :marker, ""} = Addressee.prefix("[EXAMINADOR]")
      assert {:decided, :patient, :marker, "Meu"} = Addressee.prefix("[PACIENTE] Meu")
    end

    test "waits for a split exam marker and decides it once closed (#351)" do
      assert :undecided = Addressee.prefix("[EXAMINADOR:EX")
      assert {:decided, :examiner, :exam_marker, ""} = Addressee.prefix("[EXAMINADOR:EXAME]")
    end

    test "decides on the first character that cannot start a marker" do
      assert {:decided, :patient, :missing_marker, "Meu"} = Addressee.prefix("Meu")
    end

    test "gives up on an opening bracket that never closes" do
      long = "[" <> String.duplicate("a", 40)
      assert {:decided, :patient, :missing_marker, ^long} = Addressee.prefix(long)
    end
  end

  describe "stream/2" do
    defp run_stream(pieces) do
      test_pid = self()

      {on_text, finish} =
        Addressee.stream(
          fn text -> send(test_pid, {:text, text}) end,
          fn addressee, source -> send(test_pid, {:addressee, addressee, source}) end
        )

      Enum.each(pieces, on_text)
      finish.()
    end

    test "a marker split across pieces is decided once and never forwarded" do
      assert :patient = run_stream(["[PACI", "ENTE] Meu", " nome é Ana."])

      assert_received {:addressee, :patient, :marker}
      assert_received {:text, "Meu"}
      assert_received {:text, " nome é Ana."}
      refute_received {:addressee, _, _}
      refute_received {:text, _}
    end

    test "the decision arrives before any text" do
      run_stream(["[PACIENTE] Sim."])

      assert {:messages, [{:addressee, :patient, :marker}, {:text, "Sim."}]} =
               Process.info(self(), :messages)
    end

    test "an examiner reply forwards nothing, even text after the marker" do
      assert :examiner = run_stream(["[EXAMIN", "ADOR]", " Anotado."])

      assert_received {:addressee, :examiner, :marker}
      refute_received {:text, _}
    end

    test "an exam reply split across pieces forwards nothing (#351)" do
      assert :examiner = run_stream(["[EXAMINADOR", ":EXA", "ME]", " Anotado."])

      assert_received {:addressee, :examiner, :exam_marker}
      refute_received {:text, _}
    end

    test "a reply without a marker is forwarded whole as patient-addressed" do
      assert :patient = run_stream(["A dor", " começou ontem."])

      assert_received {:addressee, :patient, :missing_marker}
      assert_received {:text, "A dor"}
      assert_received {:text, " começou ontem."}
    end

    test "a reply that ends before the marker is decided is patient-addressed" do
      assert :patient = run_stream(["[PACI"])

      assert_received {:addressee, :patient, :missing_marker}
      assert_received {:text, "[PACI"}
    end

    test "an empty reply still takes a decision" do
      assert :patient = run_stream([])
      assert_received {:addressee, :patient, :missing_marker}
      refute_received {:text, _}
    end
  end
end
