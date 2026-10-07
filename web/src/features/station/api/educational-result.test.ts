import { describe, expect, it, vi } from "vitest";
import { createApiClient } from "./client";
import { partialResult } from "../result/educational-result.fixture";

describe("educational result wire boundary", () => {
  it.each([
    { ...partialResult, schema_version: "1" },
    { ...partialResult, placeholder: "true" },
    { ...partialResult, criteria: [{ ...partialResult.criteria[0], points: 0.25 }, partialResult.criteria[1]] },
    { ...partialResult, criteria: [partialResult.criteria[0], { ...partialResult.criteria[1], points: "0" }] },
    { ...partialResult, criteria: [{ ...partialResult.criteria[0], points: "0.1" }, partialResult.criteria[1]] },
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
  it("uses v2 and preserves exact decimals and absent unresolved points", async () => {
    const fetchMock = vi.fn<typeof fetch>().mockResolvedValue(new Response(JSON.stringify(partialResult)));
    const client = createApiClient({ baseUrl: "", fetch: fetchMock });
    await expect(client.fetchResult("session/1")).resolves.toEqual(partialResult);
    expect(fetchMock.mock.calls[0][0]).toBe("/api/v2/stations/active/sessions/session%2F1/result");
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
