defmodule Backend.EducationalResultBudgetTest do
  @moduledoc """
  Invariant (issue #301): the educational result runs the rubric resolver and
  then learner feedback before answering, so both deadlines together must fit
  inside the web client's wait for the result with margin left for Jev's
  rubric calls, the network and serialization.
  """
  use ExUnit.Case, async: true

  alias Backend.Stations.RubricAssessment.Resolver

  @client Path.expand("../../../web/src/features/station/api/client.ts", __DIR__)
  @margin_ms 15_000

  defp client_timeout_ms do
    [_match, digits] =
      Regex.run(~r/const EDUCATIONAL_RESULT_TIMEOUT_MS = ([\d_]+);/, File.read!(@client))

    digits |> String.replace("_", "") |> String.to_integer()
  end

  test "the default resolver and feedback deadlines fit the web result timeout" do
    resolver_ms = Application.fetch_env!(:backend, :rubric_resolver_deadline_ms)
    feedback_ms = Application.fetch_env!(:backend, :learner_feedback_deadline_ms)

    assert resolver_ms == 30_000
    assert resolver_ms == Resolver.deadline_ms([])
    assert resolver_ms + feedback_ms + @margin_ms <= client_timeout_ms()
  end

  test "the largest runtime overrides still fit the web result timeout" do
    # `config/runtime.exs` caps resolver + feedback at 80 s.
    assert 80_000 + @margin_ms <= client_timeout_ms()
  end
end
