defmodule Backend.Stations.CaseFormatValidationTest do
  @moduledoc """
  Each validation rule of the tagged case format (issue #330) has a failing
  example: the reference acute-appendicitis case with one defect, and the
  error located at the line of the tag that carries it.
  """
  use ExUnit.Case, async: true

  alias Backend.Stations

  @case_path Path.expand("../../../priv/stations/acute-appendicitis/case.md", __DIR__)

  defp reference_case, do: File.read!(@case_path)

  # The reference case with `old` replaced by `new`; `old` must occur once.
  defp with_defect(old, new) do
    text = reference_case()
    assert [_before, _after] = String.split(text, old), "#{inspect(old)} must occur once"
    String.replace(text, old, new)
  end

  # The 1-based line of the only line of `text` that contains `fragment`.
  defp line_of(text, fragment) do
    lines =
      for {line, number} <- text |> String.split("\n") |> Enum.with_index(1),
          String.contains?(line, fragment),
          do: number

    assert [number] = lines, "#{inspect(fragment)} must be on exactly one line"
    number
  end

  defp errors(text) do
    assert {:error, errors} = Stations.parse_case(text)
    errors
  end

  defp assert_error(text, line, message) do
    errors = errors(text)

    assert %{line: line, message: message} in errors,
           "expected #{inspect(%{line: line, message: message})} in #{inspect(errors, pretty: true)}"
  end

  describe "unknown links" do
    test "a fact names an actor that is not declared" do
      text = with_defect("[FATO hda-04 ator=paciente", "[FATO hda-04 ator=medico")
      assert_error(text, line_of(text, "[FATO hda-04"), "unknown actor medico")
    end

    test "a fact links to a PEP criterion that does not exist" do
      text =
        with_defect(
          "hda-04 ator=paciente pep=item-03.criterio-2",
          "hda-04 ator=paciente pep=item-03.criterio-9"
        )

      assert_error(
        text,
        line_of(text, "[FATO hda-04"),
        "unknown PEP criterion item-03.criterio-9; expected pep=item-id.criterion-id"
      )
    end

    test "a fact links to a criterion that is not a PERGUNTA" do
      text =
        with_defect(
          "hda-04 ator=paciente pep=item-03.criterio-2",
          "hda-04 ator=paciente pep=item-06.criterio-1"
        )

      assert_error(
        text,
        line_of(text, "[FATO hda-04"),
        "pep=item-06.criterio-1 must name a PERGUNTA criterion"
      )
    end

    test "a criterion is verbalized after an impresso that does not exist" do
      text = with_defect("após=impresso-2-pcr]", "após=impresso-2-proteina]")

      assert_error(
        text,
        line_of(text, "após=impresso-2-proteina"),
        "unknown impresso impresso-2-proteina"
      )
    end

    test "a criterion is requested through an impresso that does not exist" do
      text = with_defect("impressos=impresso-2-pcr]", "impressos=impresso-9]")
      assert_error(text, line_of(text, "impressos=impresso-9"), "unknown impresso impresso-9")
    end

    test "a criterion lists no impresso in a present impressos= attribute" do
      text = with_defect("impressos=impresso-2-pcr]", "impressos=]")
      line = line_of(text, "impressos=]")

      assert line != 1
      assert_error(text, line, "impressos= must list at least one id")
    end

    test "a communication criterion checks a mandatory question that does not exist" do
      text =
        with_defect(
          "perguntas=duvida-final-01,duvida-final-02",
          "perguntas=duvida-final-01,duvida-final-09"
        )

      assert_error(
        text,
        line_of(text, "duvida-final-09"),
        "unknown mandatory question duvida-final-09"
      )
    end
  end

  describe "duplicate ids" do
    test "two facts share an id" do
      text = with_defect("[FATO hda-01-migracao ", "[FATO hda-01 ")
      first = line_of(text, "[FATO hda-01 ator=paciente pep=item-02.criterio-1]")
      second = line_of(text, "[FATO hda-01 ator=paciente pep=item-02.criterio-2]")

      assert_error(text, second, "duplicate id hda-01 (first defined on line #{first})")
    end

    test "an impresso reuses the id of an item" do
      text = with_defect("[IMPRESSO impresso-2-pcr ", "[IMPRESSO item-01 ")
      text = String.replace(text, "impresso-2-pcr", "item-01")
      item = line_of(text, "[ITEM item-01]")
      impresso = line_of(text, "[IMPRESSO item-01 ")

      assert_error(text, item, "duplicate id item-01 (first defined on line #{impresso})")
    end

    test "two criteria of one item share an id" do
      text =
        with_defect(
          "[CRITÉRIO criterio-2 tipo=COMUNICAÇÃO] Cumprimenta",
          "[CRITÉRIO criterio-1 tipo=COMUNICAÇÃO] Cumprimenta"
        )

      first = line_of(text, "] Identifica-se")
      second = line_of(text, "] Cumprimenta")

      assert_error(
        text,
        second,
        "duplicate criterion id criterio-1 (first defined on line #{first})"
      )
    end

    test "two levels of one item share a label" do
      text =
        with_defect(
          "[NÍVEL parcialmente_adequado pontos=0,1 mínimo=1]",
          "[NÍVEL adequado pontos=0,1 mínimo=1]"
        )

      first = line_of(text, "pontos=0,2 mínimo=2")
      second = line_of(text, "pontos=0,1 mínimo=1")

      assert_error(text, second, "duplicate level adequado (first defined on line #{first})")
    end
  end

  describe "missing tags" do
    test "a station tag is missing" do
      text = with_defect("[TEMA] Abdome agudo inflamatório — apendicite aguda\n", "")
      assert_error(text, 1, "missing [TEMA] tag")
    end

    test "an impresso has no content" do
      text =
        with_defect(
          "[LIBERAÇÃO] PCR; proteína C-reativa; proteína C reativa\n[CONTEÚDO]\n",
          "[LIBERAÇÃO] PCR\n"
        )

      assert_error(
        text,
        line_of(text, "[IMPRESSO impresso-2-pcr"),
        "missing [CONTEÚDO] for impresso impresso-2-pcr"
      )
    end

    test "an item has no level" do
      text =
        with_defect(
          """
          [NÍVEL adequado pontos=0,2 mínimo=2] Realiza as duas ações.
          [NÍVEL parcialmente_adequado pontos=0,1 mínimo=1] Realiza uma ação.
          [NÍVEL inadequado pontos=0 mínimo=0] Não realiza nenhuma ação.
          """,
          ""
        )

      assert_error(text, line_of(text, "[ITEM item-01]"), "missing [NÍVEL] for item item-01")
    end

    test "a fact has no actor" do
      text = with_defect("[FATO hda-04 ator=paciente ", "[FATO hda-04 ")
      assert_error(text, line_of(text, "[FATO hda-04"), "[FATO] requires the attribute ator=")
    end

    test "a fact comes before any topic" do
      text = with_defect("[TÓPICO] HDA — respostas padronizadas\n", "")
      assert_error(text, line_of(text, "[FATO hda-01 "), "[FATO] requires a preceding [TÓPICO]")
    end

    test "a PERGUNTA criterion has no fact that answers it" do
      text =
        with_defect(
          "[FATO hda-05 ator=paciente pep=item-03.criterio-3]",
          "[FATO hda-05 ator=paciente]"
        )

      assert_error(
        text,
        line_of(text, "[CRITÉRIO criterio-3 tipo=PERGUNTA] apetite"),
        "PERGUNTA criterion item-03.criterio-3 has no [FATO] with pep=item-03.criterio-3"
      )
    end

    test "a criterion type misses the attribute it requires" do
      text = with_defect("tipo=SOLICITAÇÃO impressos=impresso-2-pcr]", "tipo=SOLICITAÇÃO]")

      assert_error(
        text,
        line_of(text, "tipo=SOLICITAÇÃO] PCR"),
        "tipo=SOLICITAÇÃO requires the attribute impressos="
      )
    end

    test "a level is placed outside an item" do
      text =
        with_defect(
          "[TAREFA tarefa-1]",
          "[NÍVEL adequado pontos=1 mínimo=1] Fora de lugar.\n[TAREFA tarefa-1]"
        )

      assert_error(text, line_of(text, "Fora de lugar."), "[NÍVEL] must follow an [ITEM]")
    end
  end

  describe "points" do
    test "a level's points are not a multiple of 0,025" do
      text =
        with_defect(
          "pontos=0,1 mínimo=1] Realiza uma ação.",
          "pontos=0,11 mínimo=1] Realiza uma ação."
        )

      assert_error(text, line_of(text, "pontos=0,11"), "pontos=0,11 is not a multiple of 0,025")
    end

    test "points with an unbounded integer part are a located error, not a crash" do
      nines = String.duplicate("9", 400)

      text =
        with_defect(
          "pontos=0,1 mínimo=1] Realiza uma ação.",
          "pontos=#{nines},5 mínimo=1] Realiza uma ação."
        )

      assert [%{line: _line} | _others] = errors(text)

      assert_error(
        text,
        line_of(text, "pontos=#{nines},5"),
        "pontos must be a non-negative number, found #{nines},5"
      )
    end

    test "the item maximums do not total 10,0" do
      text =
        with_defect(
          "[NÍVEL adequado pontos=0,2 mínimo=2]",
          "[NÍVEL adequado pontos=0,3 mínimo=2]"
        )

      assert_error(
        text,
        line_of(text, "[ITEM item-01]"),
        "the item maximums sum to 10,1; the PEP must total 10,0"
      )
    end
  end

  describe "actors" do
    test "the case declares no actor" do
      text =
        reference_case()
        |> String.split("\n")
        |> Enum.reject(&String.starts_with?(&1, ["[ATOR", "[PERFIL", "[TOM", "[CONTEXTO"]))
        |> Enum.join("\n")

      assert_error(text, 1, "missing actor: the case declares no [ATOR]")
    end

    test "no actor is the patient" do
      text = with_defect("papel=paciente", "papel=acompanhante")
      assert_error(text, 1, "missing actor: no [ATOR] has papel=paciente")
    end

    # Issue #341: one `[ACOMPANHANTE]` marker cannot tell two companions apart.
    test "a second companion" do
      companions = """
      [ATOR mae papel=acompanhante idade=34 voz=feminina-adulta] Juliana Souza
      [PERFIL] Mãe do paciente.
      [TOM] Fala de forma simples.

      [ATOR pai papel=acompanhante idade=36 voz=masculina-adulta] Paulo Souza
      [PERFIL] Pai do paciente.
      [TOM] Fala pouco.

      [TÓPICO] HDA — respostas padronizadas
      """

      text = with_defect("[TÓPICO] HDA — respostas padronizadas\n", companions)

      assert_error(
        text,
        line_of(text, "[ATOR pai"),
        "only one [ATOR] may have papel=acompanhante"
      )

      assert [_one] = Enum.filter(errors(text), &(&1.message =~ "acompanhante"))
    end
  end

  describe "thresholds" do
    test "a zero-point level requires a learner action" do
      text =
        with_defect(
          "pontos=0 mínimo=0] Não realiza nenhuma ação.",
          "pontos=0 mínimo=1] Não realiza nenhuma ação."
        )

      assert_error(
        text,
        line_of(text, "Não realiza nenhuma ação."),
        "a level with pontos=0 must set mínimo=0"
      )
    end

    test "a level above zero needs no learner action" do
      text =
        with_defect(
          "pontos=0,1 mínimo=1] Realiza uma ação.",
          "pontos=0,1 mínimo=0] Realiza uma ação."
        )

      assert_error(
        text,
        line_of(text, "Realiza uma ação."),
        "a level with pontos above zero must set mínimo to at least 1"
      )
    end

    test "the thresholds decrease as points increase" do
      text =
        with_defect("pontos=0,4 mínimo=3] Investiga três", "pontos=0,4 mínimo=6] Investiga três")

      assert_error(
        text,
        line_of(text, "[ITEM item-02]"),
        "mínimo must not decrease as pontos increase in item item-02"
      )
    end

    test "the top threshold exceeds the criteria that can be performed" do
      text =
        with_defect(
          "pontos=0,8 mínimo=5] Investiga cinco",
          "pontos=0,8 mínimo=7] Investiga cinco"
        )

      assert_error(
        text,
        line_of(text, "[ITEM item-02]"),
        "mínimo=7 exceeds the 6 criteria that are not PROIBIDO"
      )
    end

    test "a threshold is not a number" do
      text = with_defect("pontos=0,2 mínimo=2]", "pontos=0,2 mínimo=dois]")

      assert_error(
        text,
        line_of(text, "mínimo=dois"),
        "mínimo must be a non-negative integer, found dois"
      )
    end
  end

  describe "tag syntax" do
    test "an unknown tag is reported" do
      text = with_defect("[ÁREA] Cirurgia Geral", "[ÁREA] Cirurgia Geral\n[DIFICULDADE] alta")
      assert_error(text, line_of(text, "[DIFICULDADE]"), "unknown tag [DIFICULDADE]")
    end

    test "a tag line without its closing bracket is reported" do
      text =
        with_defect(
          "[FATO hda-04 ator=paciente pep=item-03.criterio-2]",
          "[FATO hda-04 ator=paciente pep=item-03.criterio-2"
        )

      assert [%{line: line, message: "malformed tag line: " <> _rest} | _others] = errors(text)
      assert line == line_of(text, "[FATO hda-04")
    end

    test "an unknown attribute or flag is reported" do
      text =
        with_defect("[FATO hda-04 ator=paciente ", "[FATO hda-04 ator=paciente cor=azul URGENTE ")

      line = line_of(text, "[FATO hda-04")

      assert_error(text, line, "unknown attribute cor= on [FATO]")
      assert_error(text, line, "unknown flag URGENTE on [FATO]")
    end

    test "an attribute repeated on one tag is reported and the first value is kept" do
      text =
        with_defect(
          "pontos=0,1 mínimo=1] Realiza uma ação.",
          "pontos=0,1 pontos=0,2 mínimo=1] Realiza uma ação."
        )

      assert_error(text, line_of(text, "pontos=0,1 pontos=0,2"), "duplicate attribute pontos=")
    end

    test "errors are sorted by line" do
      text =
        "[FATO hda-04 ator=paciente pep=item-03.criterio-2]"
        |> with_defect("[FATO hda-04 ator=medico pep=item-03.criterio-2]")
        |> String.replace("[TEMA] Abdome agudo inflamatório — apendicite aguda\n", "")

      lines = text |> errors() |> Enum.map(& &1.line)
      assert lines == Enum.sort(lines)
      assert [1, _fact_line] = lines
    end
  end

  describe "encoding" do
    test "a case that is not valid UTF-8 is a located error, not a crash" do
      assert [%{line: 1, message: "case is not valid UTF-8"}] = errors(<<255, 10>>)
    end

    test "the error is located at the first line with an invalid byte" do
      text = reference_case()
      line = line_of(text, "[TAREFA tarefa-2]")
      broken = String.replace(text, "[TAREFA tarefa-2]", <<"[TAREFA tarefa-2]", 255>>)

      assert [%{line: ^line, message: "case is not valid UTF-8"}] = errors(broken)
    end
  end
end
