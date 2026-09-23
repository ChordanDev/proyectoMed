import { afterAll, beforeAll, describe, expect, it } from "vitest";
import { ApiError, createApiClient } from "../features/station/api/client";
import { startE2EHarness, type E2EHarnessInstance } from "./harness";

describe("Station E2E Happy Path", () => {
  let harness: E2EHarnessInstance;
  let client: ReturnType<typeof createApiClient>;

  beforeAll(async () => {
    harness = await startE2EHarness({
      mockOpenAIReplies: [
        "A dor começou durante uma caminhada.",
      ],
      startupTimeoutMs: 25_000,
    });
    client = createApiClient({
      baseUrl: harness.baseUrl,
    });
  }, 30_000);

  afterAll(async () => {
    if (harness) {
      await harness.stop();
    }
  });

  it("exercises the full station flow from startup through criterion-level results", async () => {
    // 1. Fetch active station metadata
    const activeStation = await client.getActiveStation();
    expect(activeStation).toMatchObject({
      station_id: "chest-pain-initial-assessment",
      version: "1.0.0",
      display_title: "Avaliação inicial de dor torácica",
      language: "pt-BR",
    });

    // 2. Start session with learner consent
    const session = await client.startSession({ audio_consent: true });
    expect(session.session_id).toBeTruthy();
    expect(session.station_id).toBe("chest-pain-initial-assessment");
    expect(session.station_version).toBe("1.0.0");
    expect(session.audio_consent).toBe(true);
    expect(new Date(session.started_at).getTime()).toBeLessThanOrEqual(
      new Date(session.expires_at).getTime(),
    );

    // 3. Exchange conversation turns
    const reply = await client.sendMessage(session.session_id, {
      role: "learner",
      modality: "text",
      text: "Quando começou a dor no peito?",
    });

    expect(reply.reply_text).toBe("A dor começou durante uma caminhada.");
    expect(reply.server_now).toBeTruthy();

    // 4. Finish session manually
    const finished = await client.finishSession(session.session_id, "user");
    expect(finished.session_id).toBe(session.session_id);
    expect(finished.status).toBe("completed");
    expect(finished.completed_at).toBeTruthy();

    // 5. Retrieve criterion-level rubric results
    const result = await client.fetchResult(session.session_id);
    expect(result.session_id).toBe(session.session_id);
    expect(result.status).toBe("completed");
    expect(Array.isArray(result.criteria)).toBe(true);
    expect(result.criteria.length).toBeGreaterThan(0);

    const onsetCriterion = result.criteria.find(
      (c) => c.id === "onset-assessment",
    );
    expect(onsetCriterion).toBeDefined();
    expect(onsetCriterion?.status).toBe("met");
    expect(Array.isArray(onsetCriterion?.evidence)).toBe(true);
    expect(onsetCriterion?.evidence.length).toBeGreaterThan(0);
    expect(onsetCriterion?.recommendation).toBe(
      "Practice opening chest pain assessments with onset questions.",
    );
  });

  it("fails with actionable diagnostics when contract boundaries are violated", async () => {
    // Non-existent session returns 404 with structured error
    await expect(
      client.sendMessage("non-existent-session-id", {
        role: "learner",
        modality: "text",
        text: "Olá",
      }),
    ).rejects.toThrow(ApiError);

    try {
      await client.sendMessage("non-existent-session-id", {
        role: "learner",
        modality: "text",
        text: "Olá",
      });
    } catch (error) {
      expect(error).toBeInstanceOf(ApiError);
      const apiError = error as ApiError;
      expect(apiError.status).toBe(404);
      expect(apiError.code).toBe("session_not_found");
      expect(apiError.message).toBeTruthy();
    }
  });
});

describe("Station E2E Technical Failure", () => {
  let harness: E2EHarnessInstance;
  let client: ReturnType<typeof createApiClient>;

  beforeAll(async () => {
    harness = await startE2EHarness({
      mockOpenAIFailureStatus: 500,
      startupTimeoutMs: 25_000,
    });
    client = createApiClient({
      baseUrl: harness.baseUrl,
    });
  }, 30_000);

  afterAll(async () => {
    if (harness) {
      await harness.stop();
    }
  });

  it("keeps feedback unavailable and recovers with a fresh session after an upstream failure", async () => {
    const failedSession = await client.startSession({ audio_consent: true });

    try {
      await client.sendMessage(failedSession.session_id, {
        role: "learner",
        modality: "text",
        text: "Quando começou a dor no peito?",
      });
      throw new Error("Expected the Station AI request to fail");
    } catch (error) {
      expect(error).toBeInstanceOf(ApiError);
      const apiError = error as ApiError;
      expect(apiError.status).toBe(502);
      expect(apiError.code).toBe("station_ai_unavailable");
      expect(apiError.message).toBe(
        "O serviço da estação de IA está temporariamente indisponível.",
      );
    }

    try {
      await client.fetchResult(failedSession.session_id);
      throw new Error("Expected results to remain unavailable");
    } catch (error) {
      expect(error).toBeInstanceOf(ApiError);
      const apiError = error as ApiError;
      expect(apiError.status).toBe(422);
      expect(apiError.code).toBe("session_not_finished");
    }

    const recoverySession = await client.startSession({ audio_consent: true });
    expect(recoverySession.session_id).toBeTruthy();
    expect(recoverySession.session_id).not.toBe(failedSession.session_id);
  });
});
