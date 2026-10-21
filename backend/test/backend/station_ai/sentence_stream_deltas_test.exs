defmodule Backend.Stations.StationAI.SentenceStreamDeltasTest do
  @moduledoc """
  Issue #313: with a `:delta` callback, `SentenceStream` hands over the raw
  reply so far on every generated piece, before the sentence it belongs to is
  complete, and aborts the deltas when a check fails.
  """
  use ExUnit.Case, async: true

  alias Backend.Stations.StationAI.SentenceStream

  defp run(pieces, opts \\ []) do
    test = self()

    generate = fn on_text ->
      Enum.each(pieces, fn piece ->
        on_text.(piece)
        # Let the caller see each piece on its own.
        Process.sleep(5)
      end)

      {:ok, Enum.join(pieces)}
    end

    SentenceStream.run(
      Keyword.merge(
        [
          generate: generate,
          verify: fn candidate, index ->
            send(test, {:event, {:verify, index, candidate}})
            :verified
          end,
          deliver: fn sentence, index, acc ->
            send(test, {:event, {:deliver, index, sentence}})
            {:cont, acc}
          end,
          delta: fn event, acc ->
            send(test, {:event, {:delta, event}})
            violation = Keyword.get(opts, :violation)

            case event do
              {_kind, raw} when is_binary(violation) ->
                if raw =~ violation, do: {:violation, acc}, else: {:cont, acc}

              _event ->
                {:cont, acc}
            end
          end,
          acc: nil
        ],
        Keyword.delete(opts, :violation)
      )
    )
  end

  defp events(acc \\ []) do
    receive do
      {:event, event} -> events([event | acc])
    after
      0 -> Enum.reverse(acc)
    end
  end

  test "the raw reply reaches the delta callback before its sentence completes" do
    result = run(["Começou ", "ontem ", "à noite. ", "Ainda dói."])

    assert result.outcome == :complete

    assert [
             {:delta, {:text, "Começou "}},
             {:delta, {:text, "Começou ontem "}},
             {:delta, {:text, "Começou ontem à noite. "}},
             {:verify, 0, "Começou ontem à noite."},
             {:deliver, 0, "Começou ontem à noite."},
             {:delta, {:text, "Começou ontem à noite. Ainda dói."}},
             {:delta, {:final, "Começou ontem à noite. Ainda dói."}},
             {:verify, 1, _},
             {:deliver, 1, " Ainda dói."}
           ] = events()
  end

  test "a closed gate stops the reply before any delta" do
    result = run(["Começou ontem."], gate: fn -> {:closed, :examiner_addressed} end)

    assert result.outcome == {:closed, :examiner_addressed}
    assert events() == []
  end

  test "a violation aborts the deltas and the reply so far takes the verification" do
    test = self()

    verify = fn candidate, index ->
      send(test, {:event, {:verify, index, candidate}})
      if candidate =~ "modelo", do: {:refused, :bounded_reply}, else: :verified
    end

    result =
      run(["Começou ontem. ", "Sou um modelo ", "de linguagem. ", "Ainda dói."],
        violation: "modelo",
        verify: verify
      )

    assert result.outcome == {:refused, :bounded_reply}
    assert result.delivered == ["Começou ontem."]

    assert [
             {:delta, {:text, "Começou ontem. "}},
             {:verify, 0, "Começou ontem."},
             {:deliver, 0, "Começou ontem."},
             {:delta, {:text, "Começou ontem. Sou um modelo "}},
             {:delta, :abort},
             {:verify, 1, "Começou ontem. Sou um modelo"}
           ] = events()
  end

  test "a violation in the first sentence follows the single regeneration" do
    test = self()

    verify = fn candidate, index ->
      send(test, {:event, {:verify, index, candidate}})
      if candidate =~ "modelo", do: {:regenerated, "Começou ontem. Ainda dói."}, else: :verified
    end

    result = run(["Sou um modelo ", "de linguagem."], violation: "modelo", verify: verify)

    assert result.outcome == :complete
    assert result.delivered == ["Começou ontem.", " Ainda dói."]

    assert [
             {:delta, {:text, "Sou um modelo "}},
             {:delta, :abort},
             {:verify, 0, "Sou um modelo"},
             {:deliver, 0, "Começou ontem."},
             {:deliver, 1, " Ainda dói."}
           ] = events()
  end

  test "a sentence the verification refuses aborts the deltas" do
    test = self()

    verify = fn candidate, index ->
      send(test, {:event, {:verify, index, candidate}})
      if index == 1, do: {:refused, :bounded_reply}, else: :verified
    end

    result = run(["Começou ontem. ", "Ainda dói."], verify: verify)

    assert result.outcome == {:refused, :bounded_reply}
    assert {:delta, :abort} in events()
  end

  test "a failed generation aborts the deltas" do
    generate = fn on_text ->
      on_text.("Começou ")
      {:error, :timeout}
    end

    result = run([], generate: generate)

    assert result.outcome == {:error, :timeout}
    assert [{:delta, {:text, "Começou "}}, {:delta, :abort}] = events()
  end
end
