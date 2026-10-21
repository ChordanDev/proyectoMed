import { describe, expect, it, vi } from "vitest";
import { createApiClient } from "./client";
import { partialResult } from "../result/educational-result.fixture";

describe("educational result wire boundary", () => {
  it.each([
    { ...partialResult, schema_version: "1" },
    { ...partialResult, placeholder: "true" },
    { ...partialResult, criteria: [{ ...partialResult.criteria[0], points: 0.25 }, partialResult.criteria[1]] },
    { ...partialResult, criteria: [partialResult.criteria[0], { ...partialResult.criteria[1], points: "0" }] },
    { ...partialResult, criteria: [{ ...partialResult.criteria[0], points: "0.01" }, partialResult.criteria[1]] },
    { ...partialResult, criteria: [{ ...partialResult.criteria[0], points: "0.0125" }, partialResult.criteria[1]] },
    { ...partialResult, criteria: [{ ...partialResult.criteria[0], points: "0.250" }, partialResult.criteria[1]] },
    { ...partialResult, criteria: [{ ...partialResult.criteria[0], max_points: "0.33" }, partialResult.criteria[1]] },
    { ...partialResult, estimates: { ...partialResult.estimates, total: "0.25" } },
    { ...partialResult, estimates: { ...partialResult.estimates, scored_subtotal: "1" } },
    { ...partialResult, estimates: { ...partialResult.estimates, unresolved: [] } },
    { ...partialResult, coverage: { ...partialResult.coverage, uncertain: 0 } },
    { ...partialResult, criteria: [{ ...partialResult.criteria[0], evidence_ids: ["fabricated"] }, partialResult.criteria[1]] },
  ])("rejects malformed or inconsistent educational payload %# without fallback", async (body) => {
    const fetchMock = vi.fn<typeof fetch>().mockResolvedValue(new Response(JSON.stringify(body)));
    const client = createApiClient({ baseUrl: "", fetch: fetchMock });
    await expect(client.fetchResult("session-1")).rejects.toMatchObject({ code: "invalid_response" });
    expect(fetchMock).toHaveBeenCalledTimes(1);
  });

  it("accepts exact complete coverage and genuine zero without using floating-point totals", async () => {
    const first = { ...partialResult.criteria[0], max_points: "1.5", points: "1.125" };
    const complete = { ...partialResult, criteria: [first], coverage: { assessed: 1, uncertain: 0, not_observable: 0, not_applicable: 0 }, estimates: { total: "1.125", scored_subtotal: "1.125", scored_max: "1.5", eligible_max: "1.5", unresolved: [] } };
    const fetchMock = vi.fn<typeof fetch>().mockResolvedValue(new Response(JSON.stringify(complete)));
    const client = createApiClient({ baseUrl: "", fetch: fetchMock });
    await expect(client.fetchResult("session-1")).resolves.toEqual(complete);
    const zero = { ...complete, criteria: [{ ...first, points: "0" }], estimates: { ...complete.estimates, total: "0", scored_subtotal: "0" } };
    fetchMock.mockResolvedValue(new Response(JSON.stringify(zero)));
    await expect(client.fetchResult("session-1")).resolves.toEqual(zero);
  });
  it.each([
    { max: "0.8", points: "0.4" },
    { max: "1.4", points: "1.2" },
    { max: "0.7", points: "0.1" },
    { max: "0.6", points: "0.3" },
    { max: "0.2", points: "0.025" },
    { max: "0.625", points: "0.375" },
  ])("accepts points in exact multiples of 0.025 ($points of $max)", async ({ max, points }) => {
    const first = { ...partialResult.criteria[0], max_points: max, points };
    const complete = { ...partialResult, criteria: [first], coverage: { assessed: 1, uncertain: 0, not_observable: 0, not_applicable: 0 }, estimates: { total: points, scored_subtotal: points, scored_max: max, eligible_max: max, unresolved: [] } };
    const client = createApiClient({ baseUrl: "", fetch: vi.fn<typeof fetch>().mockResolvedValue(new Response(JSON.stringify(complete))) });
    await expect(client.fetchResult("session-1")).resolves.toEqual(complete);
  });

  it("reconciles tenth totals with integer arithmetic", async () => {
    const [first, second] = partialResult.criteria;
    const criteria = [{ ...first, max_points: "0.2", points: "0.1" }, { ...first, id: second.id, max_points: "0.2", points: "0.2" }];
    const complete = { ...partialResult, criteria, coverage: { assessed: 2, uncertain: 0, not_observable: 0, not_applicable: 0 }, estimates: { total: "0.3", scored_subtotal: "0.3", scored_max: "0.4", eligible_max: "0.4", unresolved: [] } };
    const client = createApiClient({ baseUrl: "", fetch: vi.fn<typeof fetch>().mockResolvedValue(new Response(JSON.stringify(complete))) });
    await expect(client.fetchResult("session-1")).resolves.toEqual(complete);
  });

  it("uses v2 and preserves exact decimals and absent unresolved points", async () => {
    const fetchMock = vi.fn<typeof fetch>().mockResolvedValue(new Response(JSON.stringify(partialResult)));
    const client = createApiClient({ baseUrl: "", fetch: fetchMock });
    await expect(client.fetchResult("session/1")).resolves.toEqual(partialResult);
    expect(fetchMock.mock.calls[0][0]).toBe("/api/v2/stations/active/sessions/session%2F1/result");
  });

  // Issue #291: an uncertain criterion may carry the evidence of what the learner asked.
  it("accepts evidence on an uncertain criterion", async () => {
    const evidence = [{ id: "turn-1", role: "learner" as const, text: "Onde começou a dor?" }];
    const uncertain = { ...partialResult.criteria[1], evidence_ids: ["turn-1"], evidence };
    const body = { ...partialResult, criteria: [partialResult.criteria[0], uncertain] };
    const client = createApiClient({ baseUrl: "", fetch: vi.fn<typeof fetch>().mockResolvedValue(new Response(JSON.stringify(body))) });
    await expect(client.fetchResult("session-1")).resolves.toEqual(body);
  });

  it.each(["not_observable", "not_applicable"] as const)("still rejects evidence on a %s criterion", async (status) => {
    const reason = status === "not_observable" ? "required_modality_unavailable" : "authored_exclusion";
    const evidence = [{ id: "turn-1", role: "learner", text: "Onde começou a dor?" }];
    const criterion = { ...partialResult.criteria[1], status, reason, evidence_ids: ["turn-1"], evidence };
    const coverage = { assessed: 1, uncertain: 0, not_observable: status === "not_observable" ? 1 : 0, not_applicable: status === "not_applicable" ? 1 : 0 };
    const unresolved = status === "not_observable" ? [{ id: criterion.id, status }] : [];
    const eligible_max = status === "not_observable" ? "1.25" : "0.25";
    const body = { ...partialResult, criteria: [partialResult.criteria[0], criterion], coverage, estimates: { ...partialResult.estimates, eligible_max, unresolved, total: unresolved.length === 0 ? "0.25" : null } };
    const valid = { ...body, criteria: [partialResult.criteria[0], { ...criterion, evidence_ids: [], evidence: [] }] };
    const fetchMock = vi.fn<typeof fetch>().mockResolvedValue(new Response(JSON.stringify(valid)));
    const client = createApiClient({ baseUrl: "", fetch: fetchMock });
    await expect(client.fetchResult("session-1")).resolves.toEqual(valid);
    fetchMock.mockResolvedValue(new Response(JSON.stringify(body)));
    await expect(client.fetchResult("session-1")).rejects.toMatchObject({ code: "invalid_response" });
  });

  it("rejects legacy success and never falls back after a technical failure", async () => {
    const fetchMock = vi.fn<typeof fetch>().mockResolvedValue(new Response(JSON.stringify({ error: "invalid_attempt", message: "Tentativa inválida" }), { status: 502 }));
    const client = createApiClient({ baseUrl: "", fetch: fetchMock });
    await expect(client.fetchResult("s")).rejects.toMatchObject({ code: "invalid_attempt" });
    expect(fetchMock).toHaveBeenCalledTimes(1);
    fetchMock.mockResolvedValue(new Response(JSON.stringify({ session_id: "s", status: "completed", criteria: [] })));
    await expect(client.fetchResult("s")).rejects.toMatchObject({ code: "invalid_response" });
  });
});
