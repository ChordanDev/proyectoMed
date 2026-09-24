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

describe("Station E2E Session Expiry", () => {
  let harness: E2EHarnessInstance;
  let client: ReturnType<typeof createApiClient>;

  beforeAll(async () => {
    harness = await startE2EHarness({
      mockOpenAIReplies: [
        "A dor começou durante uma caminhada.",
      ],
      conversationTimeoutMs: 500,
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

  it("handles expired and missing sessions predictably, ensures no stale result, and recovers", async () => {
    // 1. Expired active session scenario
    const expiredSession = await client.startSession({ audio_consent: true });
    expect(expiredSession.session_id).toBeTruthy();

    // Wait for session to expire (timeout is 500ms)
    await new Promise((resolve) => setTimeout(resolve, 600));

    // Attempting to send a message on an expired session returns documented 410 session_expired
    try {
      await client.sendMessage(expiredSession.session_id, {
        role: "learner",
        modality: "text",
        text: "Quando começou a dor?",
      });
      throw new Error("Expected sendMessage to fail on expired session");
    } catch (error) {
      expect(error).toBeInstanceOf(ApiError);
      const apiError = error as ApiError;
      expect(apiError.status).toBe(410);
      expect(apiError.code).toBe("session_expired");
      expect(apiError.message).toBe("A sessão expirou.");
    }

    // Attempting to finish an expired session also returns 410 or 404 (purged)
    try {
      await client.finishSession(expiredSession.session_id, "user");
      throw new Error("Expected finishSession to fail on expired session");
    } catch (error) {
      expect(error).toBeInstanceOf(ApiError);
      const apiError = error as ApiError;
      expect([404, 410]).toContain(apiError.status);
      expect(["session_not_found", "session_expired"]).toContain(apiError.code);
    }

    // Attempting to retrieve results on the expired session fails (no stale result returned)
    try {
      await client.fetchResult(expiredSession.session_id);
      throw new Error("Expected fetchResult to fail on expired session");
    } catch (error) {
      expect(error).toBeInstanceOf(ApiError);
      const apiError = error as ApiError;
      expect([404, 410]).toContain(apiError.status);
      expect(["session_not_found", "session_expired"]).toContain(apiError.code);
    }

    // 2. Missing session scenario returns 404 session_not_found with no result
    const missingSessionId = "00000000-0000-0000-0000-000000000000";
    try {
      await client.fetchResult(missingSessionId);
      throw new Error("Expected fetchResult to fail on missing session");
    } catch (error) {
      expect(error).toBeInstanceOf(ApiError);
      const apiError = error as ApiError;
      expect(apiError.status).toBe(404);
      expect(apiError.code).toBe("session_not_found");
      expect(apiError.message).toBe("Sessão não encontrada.");
    }

    // 3. Completed session that subsequently expires: verify stale result is wiped
    const completedThenExpired = await client.startSession({ audio_consent: true });
    await client.sendMessage(completedThenExpired.session_id, {
      role: "learner",
      modality: "text",
      text: "Quando começou a dor no peito?",
    });
    const finished = await client.finishSession(completedThenExpired.session_id, "user");
    expect(finished.status).toBe("completed");

    // Before expiry, result is available
    const freshResult = await client.fetchResult(completedThenExpired.session_id);
    expect(freshResult.status).toBe("completed");
    expect(freshResult.criteria.length).toBeGreaterThan(0);

    // Wait for the session to expire
    await new Promise((resolve) => setTimeout(resolve, 600));

    // After expiry, fetching result fails (no stale result served)
    try {
      await client.fetchResult(completedThenExpired.session_id);
      throw new Error("Expected fetchResult to fail after completed session expired");
    } catch (error) {
      expect(error).toBeInstanceOf(ApiError);
      const apiError = error as ApiError;
      expect([404, 410]).toContain(apiError.status);
      expect(["session_not_found", "session_expired"]).toContain(apiError.code);
    }

    // 4. Appropriate recovery: client starts a fresh session and interacts successfully
    const recoverySession = await client.startSession({ audio_consent: true });
    expect(recoverySession.session_id).toBeTruthy();
    expect(recoverySession.session_id).not.toBe(expiredSession.session_id);
    expect(recoverySession.session_id).not.toBe(completedThenExpired.session_id);

    const reply = await client.sendMessage(recoverySession.session_id, {
      role: "learner",
      modality: "text",
      text: "Quando começou a dor no peito?",
    });
    expect(reply.reply_text).toBe("A dor começou durante uma caminhada.");
  });
});
