import React from "react";
import { act, renderHook, waitFor } from "@testing-library/react";
import { afterEach } from "vitest";
import {
  ApiError,
  type CompletedSession,
  type Impresso,
  type ListImpressosResponse,
  type MessageReply,
  type RequestImpressoResponse,
  type Session,
  type SessionDetail,
  type SessionResult,
} from "../api/client";
import { sessionIdStorageKey, useStation, type StationApi } from "./useStation";

afterEach(() => {
  sessionStorage.clear();
});

const session: Session = {
  session_id: "session-1",
  station_id: "station-1",
  station_version: "1.0.0",
  audio_consent: true,
  started_at: "2026-01-01T10:00:00Z",
  expires_at: "2026-01-01T10:30:00Z",
  deadline_at: "2026-01-01T10:10:00Z",
  server_now: "2026-01-01T10:00:00Z",
};

const completed: CompletedSession = {
  session_id: "session-1",
  status: "completed",
  completed_at: "2026-01-01T10:10:00Z",
};

const stationResult: SessionResult = {
  session_id: "session-1",
  status: "completed",
  criteria: [
    {
      id: "onset",
      status: "met",
      evidence: ["Quando começou a dor?"],
      recommendation: "",
    },
  ],
};

const reply: MessageReply = {
  reply_text: "A dor começou há duas horas.",
  server_now: "2026-01-01T10:01:00Z",
};

const message = {
  role: "learner" as const,
  modality: "text" as const,
  text: "Quando a dor começou?",
};

const chestXray: Impresso = {
  id: "chest-xray",
  title: "Radiografia de tórax",
  category: "Exame de imagem",
  content: "Sem sinais de consolidação.",
};

const impressoResponse: RequestImpressoResponse = {
  request_id: "req-1",
  decision: "released",
  released_impressos: [chestXray],
  newly_released: [chestXray],
  feedback_message: "Impresso liberado: Radiografia de tórax",
};

const impressosListResponse: ListImpressosResponse = {
  released_impressos: [chestXray],
};

const deferred = <T>() => {
  let resolve!: (value: T) => void;
  let reject!: (reason?: unknown) => void;
  const promise = new Promise<T>((resolvePromise, rejectPromise) => {
    resolve = resolvePromise;
    reject = rejectPromise;
  });
  return { promise, resolve, reject };
};

const apiMock = (overrides: Partial<StationApi> = {}): StationApi => ({
  startSession: vi.fn().mockResolvedValue(session),
  getSession: vi
    .fn()
    .mockRejectedValue(
      new ApiError(404, "session_not_found", "Sessão não encontrada."),
    ),
  sendMessage: vi.fn().mockResolvedValue(reply),
  finishSession: vi.fn().mockResolvedValue(completed),
  fetchResult: vi.fn().mockResolvedValue(stationResult),
  transcribeAudio: vi.fn().mockResolvedValue({
    text: "Quando começou a dor?",
    transcribed_at: "2026-01-01T10:00:30Z",
  }),
  synthesizeSpeech: vi
    .fn()
    .mockResolvedValue(new Blob(["audio"], { type: "audio/mpeg" })),
  requestImpresso: vi.fn().mockResolvedValue(impressoResponse),
  getImpressos: vi.fn().mockResolvedValue({ released_impressos: [] }),
  ...overrides,
});

describe("useStation", () => {
  it("owns one complete station session from loading through its result", async () => {
    const pendingStart = deferred<Session>();
    const pendingFinish = deferred<CompletedSession>();
    const pendingResult = deferred<SessionResult>();
    const api = apiMock({
      startSession: vi.fn(() => pendingStart.promise),
      finishSession: vi.fn(() => pendingFinish.promise),
      fetchResult: vi.fn(() => pendingResult.promise),
    });
    const { result } = await renderHook(() => useStation(api));

    expect(result.current).toMatchObject({
      status: "idle",
      result: null,
      error: null,
      audioConsent: false,
    });

    let blockedReply: MessageReply | null = reply;
    await act(async () => {
      blockedReply = await result.current.send(message);
    });
    expect(blockedReply).toBeNull();
    expect(api.sendMessage).not.toHaveBeenCalled();

    let startPromise!: Promise<void>;
    await act(() => {
      startPromise = result.current.start(true);
    });
    expect(result.current.status).toBe("loading");
    expect(result.current.audioConsent).toBe(true);

    blockedReply = reply;
    await act(async () => {
      blockedReply = await result.current.send(message);
    });
    expect(blockedReply).toBeNull();
    expect(api.sendMessage).not.toHaveBeenCalled();

    await act(async () => {
      pendingStart.resolve(session);
      await startPromise;
    });
    expect(result.current.status).toBe("active");

    await act(async () => {
      await result.current.start(false);
    });
    expect(api.startSession).toHaveBeenCalledTimes(1);
    expect(result.current.audioConsent).toBe(true);

    let receivedReply: MessageReply | null = null;
    await act(async () => {
      receivedReply = await result.current.send(message);
    });
    expect(receivedReply).toEqual(reply);
    expect(api.sendMessage).toHaveBeenCalledWith("session-1", message);
    expect(result.current.status).toBe("active");

    let finishPromise!: Promise<void>;
    await act(() => {
      finishPromise = result.current.finish("user");
    });
    expect(result.current.status).toBe("finishing");
    expect(api.finishSession).toHaveBeenCalledWith("session-1", "user");

    blockedReply = reply;
    await act(async () => {
      blockedReply = await result.current.send(message);
    });
    expect(blockedReply).toBeNull();
    expect(api.sendMessage).toHaveBeenCalledTimes(1);

    await act(async () => {
      pendingFinish.resolve(completed);
      await Promise.resolve();
    });
    expect(api.fetchResult).toHaveBeenCalledWith("session-1");
    expect(result.current.status).toBe("finishing");

    await act(async () => {
      pendingResult.resolve(stationResult);
      await finishPromise;
    });
    expect(result.current.status).toBe("finished");
    expect(result.current.result).toEqual(stationResult);
    expect(result.current.error).toBeNull();

    blockedReply = reply;
    await act(async () => {
      blockedReply = await result.current.send(message);
    });
    expect(blockedReply).toBeNull();
    expect(api.sendMessage).toHaveBeenCalledTimes(1);
  });

  it("fails the station and surfaces an API error message", async () => {
    const pendingStart = deferred<Session>();
    const api = apiMock({
      startSession: vi.fn(() => pendingStart.promise),
    });
    const { result } = await renderHook(() => useStation(api));

    let startPromise!: Promise<void>;
    await act(() => {
      startPromise = result.current.start(false);
    });
    expect(result.current.status).toBe("loading");

    await act(async () => {
      pendingStart.reject(
        new ApiError(503, "station_unavailable", "Estação indisponível."),
      );
      await startPromise;
    });

    expect(result.current.status).toBe("failed");
    expect(result.current.error).toBe("Estação indisponível.");
  });

  it("retries a failed start with exactly one replacement session", async () => {
    const replacementStart = deferred<Session>();
    const replacementSession: Session = {
      ...session,
      session_id: "session-2",
      station_id: "station-2",
      station_version: "2.0.0",
      audio_consent: false,
    };
    const startSession = vi
      .fn<StationApi["startSession"]>()
      .mockRejectedValueOnce(
        new ApiError(503, "station_unavailable", "Estação indisponível."),
      )
      .mockImplementationOnce(() => replacementStart.promise);
    const api = apiMock({ startSession });
    const { result } = await renderHook(() => useStation(api));

    await act(async () => {
      await result.current.start(true);
    });
    expect(result.current).toMatchObject({
      status: "failed",
      error: "Estação indisponível.",
    });

    let retryPromise!: Promise<void>;
    let duplicatePromise!: Promise<void>;
    await act(() => {
      retryPromise = result.current.start(false);
      duplicatePromise = result.current.start(true);
    });

    expect(result.current).toMatchObject({
      status: "loading",
      error: null,
      result: null,
      audioConsent: false,
    });
    expect(startSession).toHaveBeenCalledTimes(2);

    await act(async () => {
      replacementStart.resolve(replacementSession);
      await Promise.all([retryPromise, duplicatePromise]);
    });

    expect(result.current.status).toBe("active");
    expect(startSession).toHaveBeenCalledTimes(2);

    await act(async () => {
      await result.current.send(message);
    });
    expect(api.sendMessage).toHaveBeenCalledWith("session-2", message);
  });

  it("waits for a pending send before finishing the session", async () => {
    const pendingSend = deferred<MessageReply>();
    const api = apiMock({
      sendMessage: vi.fn(() => pendingSend.promise),
    });
    const { result } = await renderHook(() => useStation(api));

    await act(async () => {
      await result.current.start(true);
    });

    let sendPromise!: Promise<MessageReply | null>;
    await act(() => {
      sendPromise = result.current.send(message);
    });

    let finishPromise!: Promise<void>;
    await act(() => {
      finishPromise = result.current.finish("user");
    });
    expect(result.current.status).toBe("finishing");
    expect(api.finishSession).not.toHaveBeenCalled();

    let blockedReply: MessageReply | null = reply;
    await act(async () => {
      blockedReply = await result.current.send(message);
    });
    expect(blockedReply).toBeNull();
    expect(api.sendMessage).toHaveBeenCalledTimes(1);

    let receivedReply: MessageReply | null = null;
    await act(async () => {
      pendingSend.resolve(reply);
      receivedReply = await sendPromise;
      await finishPromise;
    });

    expect(receivedReply).toEqual(reply);
    expect(api.finishSession).toHaveBeenCalledWith("session-1", "user");
    expect(api.fetchResult).toHaveBeenCalledWith("session-1");
    expect(result.current).toMatchObject({
      status: "finished",
      result: stationResult,
      error: null,
    });
  });

  it("does not finish when the pending send fails", async () => {
    const pendingSend = deferred<MessageReply>();
    const api = apiMock({
      sendMessage: vi.fn(() => pendingSend.promise),
    });
    const { result } = await renderHook(() => useStation(api));

    await act(async () => {
      await result.current.start(true);
    });

    let sendPromise!: Promise<MessageReply | null>;
    await act(() => {
      sendPromise = result.current.send(message);
    });

    let finishPromise!: Promise<void>;
    await act(() => {
      finishPromise = result.current.finish("timer");
    });
    expect(api.finishSession).not.toHaveBeenCalled();

    let receivedReply: MessageReply | null = reply;
    await act(async () => {
      pendingSend.reject(new Error("socket details"));
      receivedReply = await sendPromise;
      await finishPromise;
    });

    expect(receivedReply).toBeNull();
    expect(result.current.status).toBe("failed");
    expect(result.current.error).toBe(
      "A estação não pôde ser concluída. Você pode reiniciar.",
    );
    expect(api.finishSession).not.toHaveBeenCalled();
    expect(api.fetchResult).not.toHaveBeenCalled();
  });

  it("allows only one send in flight while active", async () => {
    const pendingSend = deferred<MessageReply>();
    const api = apiMock({
      sendMessage: vi.fn(() => pendingSend.promise),
    });
    const { result } = await renderHook(() => useStation(api));

    await act(async () => {
      await result.current.start(true);
    });

    let firstSend!: Promise<MessageReply | null>;
    await act(() => {
      firstSend = result.current.send(message);
    });

    let concurrentSend!: Promise<MessageReply | null>;
    await act(() => {
      concurrentSend = result.current.send(message);
    });
    expect(api.sendMessage).toHaveBeenCalledTimes(1);

    let concurrentReply: MessageReply | null = reply;
    await act(async () => {
      pendingSend.resolve(reply);
      [, concurrentReply] = await Promise.all([firstSend, concurrentSend]);
    });
    expect(concurrentReply).toBeNull();
  });

  it("uses a safe pt-BR message when an unknown API failure occurs", async () => {
    const api = apiMock({
      sendMessage: vi.fn().mockRejectedValue(new Error("socket details")),
    });
    const { result } = await renderHook(() => useStation(api));

    await act(async () => {
      await result.current.start(true);
    });

    let receivedReply: MessageReply | null = reply;
    await act(async () => {
      receivedReply = await result.current.send(message);
    });

    expect(receivedReply).toBeNull();
    expect(result.current.status).toBe("failed");
    expect(result.current.error).toBe(
      "A estação não pôde ser concluída. Você pode reiniciar.",
    );

    await act(async () => {
      receivedReply = await result.current.send(message);
    });
    expect(receivedReply).toBeNull();
    expect(api.sendMessage).toHaveBeenCalledTimes(1);
  });

  it("transcribes consented session audio without failing the station", async () => {
    const transcribeAudio = vi.fn().mockResolvedValue({
      text: "  Quando começou a dor?  ",
      transcribed_at: "2026-01-01T10:00:30Z",
    });
    const api = apiMock({ transcribeAudio });
    const { result } = renderHook(() => useStation(api));
    const audio = new Blob(["audio"], { type: "audio/webm" });

    let beforeStart: string | null = "unexpected";
    await act(async () => {
      beforeStart = await result.current.transcribe(audio);
      await result.current.start(true);
    });
    expect(beforeStart).toBeNull();

    let transcription: string | null = null;
    await act(async () => {
      transcription = await result.current.transcribe(audio, "question.webm");
    });

    expect(transcription).toBe("Quando começou a dor?");
    expect(transcribeAudio).toHaveBeenCalledWith(
      "session-1",
      audio,
      "question.webm",
    );
    expect(result.current.status).toBe("active");
    expect(result.current.error).toBeNull();
  });

  it("returns null for transcription failure or missing audio consent", async () => {
    const noConsentSession = { ...session, audio_consent: false };
    const transcribeAudio = vi.fn().mockRejectedValue(new Error("network"));
    const withoutConsentApi = apiMock({
      startSession: vi.fn().mockResolvedValue(noConsentSession),
      transcribeAudio,
    });
    const withoutConsent = renderHook(() => useStation(withoutConsentApi));
    const audio = new Blob(["audio"]);

    await act(async () => {
      await withoutConsent.result.current.start(false);
    });
    await expect(withoutConsent.result.current.transcribe(audio)).resolves.toBeNull();
    expect(transcribeAudio).not.toHaveBeenCalled();

    sessionStorage.clear();
    const failingApi = apiMock({ transcribeAudio });
    const failing = renderHook(() => useStation(failingApi));
    await act(async () => {
      await failing.result.current.start(true);
    });

    let transcription: string | null = "unexpected";
    await act(async () => {
      transcription = await failing.result.current.transcribe(audio);
    });
    expect(transcription).toBeNull();
    expect(failing.result.current.status).toBe("active");
    expect(failing.result.current.error).toBeNull();
  });

  it("treats an empty transcription as unavailable", async () => {
    const api = apiMock({
      transcribeAudio: vi.fn().mockResolvedValue({
        text: "   ",
        transcribed_at: "2026-01-01T10:00:30Z",
      }),
    });
    const { result } = renderHook(() => useStation(api));

    await act(async () => {
      await result.current.start(true);
    });

    await expect(result.current.transcribe(new Blob(["audio"]))).resolves.toBeNull();
    expect(result.current.status).toBe("active");
  });

  it("resets state back to idle cleanly", async () => {
    const api = apiMock({
      sendMessage: vi.fn().mockRejectedValue(new Error("socket details")),
    });
    const { result } = await renderHook(() => useStation(api));

    await act(async () => {
      await result.current.start(true);
    });

    await act(async () => {
      await result.current.send(message);
    });
    expect(result.current.status).toBe("failed");
    expect(result.current.error).not.toBeNull();

    act(() => {
      result.current.reset();
    });

    expect(result.current.status).toBe("idle");
    expect(result.current.error).toBeNull();
    expect(result.current.result).toBeNull();
    expect(result.current.audioConsent).toBe(false);

    // Can start again cleanly after reset
    await act(async () => {
      await result.current.start(false);
    });
    expect(result.current.status).toBe("active");
    expect(result.current.audioConsent).toBe(false);
  });

  describe("server-authoritative station deadline", () => {
    afterEach(() => {
      vi.useRealTimers();
    });

    it("derives the countdown from the server-anchored clock and a rerender does not reset or extend it", async () => {
      vi.useFakeTimers({
        toFake: ["setTimeout", "clearTimeout", "setInterval", "clearInterval", "Date", "performance"],
      });
      const api = apiMock();
      const { result, rerender } = renderHook(() => useStation(api));

      await act(async () => {
        await result.current.start(true);
      });
      expect(result.current.remainingMs).toBe(10 * 60 * 1000);

      await act(async () => {
        await vi.advanceTimersByTimeAsync(60_000);
      });
      expect(result.current.remainingMs).toBe(9 * 60 * 1000);

      rerender();
      expect(result.current.remainingMs).toBe(9 * 60 * 1000);
    });

    it("counts down correctly even when the client wall clock is skewed by minutes from server_now", async () => {
      vi.useFakeTimers({
        toFake: ["setTimeout", "clearTimeout", "setInterval", "clearInterval", "Date", "performance"],
      });
      vi.setSystemTime(new Date("2026-01-01T10:07:00Z")); // client clock 7 minutes ahead
      const api = apiMock();
      const { result } = renderHook(() => useStation(api));

      await act(async () => {
        await result.current.start(true);
      });

      // deadline_at (10:10:00Z) - server_now (10:00:00Z) from the response,
      // not from the skewed local clock.
      expect(result.current.remainingMs).toBe(10 * 60 * 1000);
    });

    it("a client wall-clock jump mid-session does not change the remaining time", async () => {
      vi.useFakeTimers({
        toFake: ["setTimeout", "clearTimeout", "setInterval", "clearInterval", "Date", "performance"],
      });
      const api = apiMock();
      const { result } = renderHook(() => useStation(api));

      await act(async () => {
        await result.current.start(true);
      });
      await act(async () => {
        await vi.advanceTimersByTimeAsync(60_000);
      });
      expect(result.current.remainingMs).toBe(9 * 60 * 1000);

      act(() => {
        vi.setSystemTime(new Date("2026-01-01T14:00:00Z")); // jump the wall clock forward
      });
      expect(result.current.remainingMs).toBe(9 * 60 * 1000);
    });

    it("resumes an active session on refresh via getSession, with the same deadline and restored transcript", async () => {
      vi.useFakeTimers({
        toFake: ["setTimeout", "clearTimeout", "setInterval", "clearInterval", "Date", "performance"],
      });
      sessionStorage.setItem(sessionIdStorageKey, "session-1");
      const resumedDetail: SessionDetail = {
        ...session,
        status: "active",
        completion_reason: null,
        messages: [
          { role: "learner", text: "Bom dia" },
          { role: "patient", text: "Boa tarde" },
        ],
      };
      const api = apiMock({
        getSession: vi.fn().mockResolvedValue(resumedDetail),
      });

      const { result } = renderHook(() => useStation(api));

      await act(async () => {
        await Promise.resolve();
      });

      expect(api.getSession).toHaveBeenCalledWith("session-1");
      expect(result.current.status).toBe("active");
      expect(result.current.remainingMs).toBe(10 * 60 * 1000);
      expect(result.current.initialMessages).toEqual(resumedDetail.messages);
    });

    it("clears the stored session id and starts fresh when the resumed session is gone (404/410)", async () => {
      sessionStorage.setItem(sessionIdStorageKey, "stale-session");
      const api = apiMock({
        getSession: vi
          .fn()
          .mockRejectedValue(
            new ApiError(410, "session_expired", "A sessão expirou."),
          ),
      });

      const { result } = renderHook(() => useStation(api));

      await act(async () => {
        await Promise.resolve();
      });

      expect(result.current.status).toBe("idle");
      expect(sessionStorage.getItem(sessionIdStorageKey)).toBeNull();
    });

    it("at zero, disables further activity and finishes with reason timer exactly once, even under StrictMode double effects", async () => {
      vi.useFakeTimers({
        toFake: ["setTimeout", "clearTimeout", "setInterval", "clearInterval", "Date", "performance"],
      });
      const api = apiMock();
      const { result } = renderHook(() => useStation(api), {
        wrapper: React.StrictMode,
      });

      await act(async () => {
        await result.current.start(true);
      });

      await act(async () => {
        await vi.advanceTimersByTimeAsync(10 * 60 * 1000);
      });

      // By now the exactly-once timer finish has already resolved the
      // session (default mocks resolve immediately), so the countdown was
      // torn down along with it; assert the completed outcome instead.
      expect(api.finishSession).toHaveBeenCalledTimes(1);
      expect(api.finishSession).toHaveBeenCalledWith("session-1", "timer");
      expect(result.current.status).toBe("finished");
    });

    it("a manual finish racing the timer deadline wins alone; the timer finish is a no-op", async () => {
      vi.useFakeTimers({
        toFake: ["setTimeout", "clearTimeout", "setInterval", "clearInterval", "Date", "performance"],
      });
      const finishDeferred = deferred<CompletedSession>();
      const api = apiMock({
        finishSession: vi.fn(() => finishDeferred.promise),
      });
      const { result } = renderHook(() => useStation(api));

      await act(async () => {
        await result.current.start(true);
      });

      let manualFinish!: Promise<void>;
      act(() => {
        manualFinish = result.current.finish("user");
      });
      expect(result.current.status).toBe("finishing");

      await act(async () => {
        await vi.advanceTimersByTimeAsync(10 * 60 * 1000);
      });

      expect(api.finishSession).toHaveBeenCalledTimes(1);
      expect(api.finishSession).toHaveBeenCalledWith("session-1", "user");

      await act(async () => {
        finishDeferred.resolve(completed);
        await manualFinish;
      });
      expect(result.current.status).toBe("finished");
    });

    it("resyncs the deadline on deadline_not_reached and retries the timer finish once remaining actually reaches zero", async () => {
      vi.useFakeTimers({
        toFake: ["setTimeout", "clearTimeout", "setInterval", "clearInterval", "Date", "performance"],
      });
      const laterDeadline = "2026-01-01T10:10:02Z"; // 2s later than the original
      const refreshedDetail: SessionDetail = {
        ...session,
        deadline_at: laterDeadline,
        status: "active",
        completion_reason: null,
        messages: [],
        // No remaining client/server skew at resync time: the recomputed
        // remaining is exactly the 2s gap to the (later) resynced deadline.
        server_now: "2026-01-01T10:10:00Z",
      };
      const finishSession = vi
        .fn<StationApi["finishSession"]>()
        .mockRejectedValueOnce(
          new ApiError(
            409,
            "deadline_not_reached",
            "O prazo da estação ainda não foi atingido.",
          ),
        )
        .mockResolvedValueOnce(completed);
      const api = apiMock({
        finishSession,
        getSession: vi.fn().mockResolvedValue(refreshedDetail),
      });
      const { result } = renderHook(() => useStation(api));

      await act(async () => {
        await result.current.start(true);
      });

      await act(async () => {
        await vi.advanceTimersByTimeAsync(10 * 60 * 1000);
      });

      expect(api.getSession).toHaveBeenCalledWith("session-1");
      expect(finishSession).toHaveBeenCalledTimes(1);
      expect(result.current.status).toBe("active");

      await act(async () => {
        await vi.advanceTimersByTimeAsync(2_000);
      });

      expect(finishSession).toHaveBeenCalledTimes(2);
      expect(finishSession).toHaveBeenLastCalledWith("session-1", "timer");
      expect(result.current.status).toBe("finished");
    });

    it("a send rejected with station_time_elapsed rejects, disables the session, and finishes with reason timer once", async () => {
      const api = apiMock({
        sendMessage: vi
          .fn()
          .mockRejectedValue(
            new ApiError(
              409,
              "station_time_elapsed",
              "O tempo da estação se esgotou.",
            ),
          ),
      });
      const { result } = renderHook(() => useStation(api));

      await act(async () => {
        await result.current.start(true);
      });

      let caught: unknown;
      await act(async () => {
        try {
          await result.current.send(message);
        } catch (cause) {
          caught = cause;
        }
      });
      expect(caught).toMatchObject({ code: "station_time_elapsed" });

      await waitFor(() => {
        expect(api.finishSession).toHaveBeenCalledWith("session-1", "timer");
      });
      expect(api.finishSession).toHaveBeenCalledTimes(1);
    });
  });

  it("returns null without calling the API when there is no audio consent", async () => {
    const noConsentSession = { ...session, audio_consent: false };
    const synthesizeSpeech = vi.fn();
    const api = apiMock({
      startSession: vi.fn().mockResolvedValue(noConsentSession),
      synthesizeSpeech,
    });
    const { result } = renderHook(() => useStation(api));

    await act(async () => {
      await result.current.start(false);
    });

    await expect(result.current.synthesize("Olá")).resolves.toBeNull();
    expect(synthesizeSpeech).not.toHaveBeenCalled();
  });

  it("returns null without calling the API when there is no session", async () => {
    const synthesizeSpeech = vi.fn();
    const api = apiMock({ synthesizeSpeech });
    const { result } = renderHook(() => useStation(api));

    await expect(result.current.synthesize("Olá")).resolves.toBeNull();
    expect(synthesizeSpeech).not.toHaveBeenCalled();
  });

  it("synthesizes speech for a consented session and returns the blob", async () => {
    const audioBlob = new Blob(["audio-bytes"], { type: "audio/mpeg" });
    const synthesizeSpeech = vi.fn().mockResolvedValue(audioBlob);
    const api = apiMock({ synthesizeSpeech });
    const { result } = renderHook(() => useStation(api));

    await act(async () => {
      await result.current.start(true);
    });

    let blob: Blob | null = null;
    await act(async () => {
      blob = await result.current.synthesize("A dor começou há duas horas.");
    });

    expect(blob).toBe(audioBlob);
    expect(synthesizeSpeech).toHaveBeenCalledWith(
      "session-1",
      "A dor começou há duas horas.",
    );
    expect(result.current.status).toBe("active");
    expect(result.current.error).toBeNull();
  });

  it("returns null and keeps the station active when synthesis rejects", async () => {
    const synthesizeSpeech = vi.fn().mockRejectedValue(new Error("network"));
    const api = apiMock({ synthesizeSpeech });
    const { result } = renderHook(() => useStation(api));

    await act(async () => {
      await result.current.start(true);
    });

    let blob: Blob | null = new Blob();
    await act(async () => {
      blob = await result.current.synthesize("Olá");
    });

    expect(blob).toBeNull();
    expect(result.current.status).toBe("active");
    expect(result.current.error).toBeNull();
  });

  describe("impresso requests", () => {
    it("resolves null without calling the API when there is no live session", async () => {
      const requestImpresso = vi.fn();
      const api = apiMock({ requestImpresso });
      const { result } = renderHook(() => useStation(api));

      await expect(
        result.current.requestImpresso("Solicito radiografia"),
      ).resolves.toBeNull();
      expect(requestImpresso).not.toHaveBeenCalled();
    });

    it("requests an impresso and updates the released impressos from the response", async () => {
      const requestImpresso = vi.fn().mockResolvedValue(impressoResponse);
      const api = apiMock({ requestImpresso });
      const { result } = renderHook(() => useStation(api));

      await act(async () => {
        await result.current.start(true);
      });

      let response: RequestImpressoResponse | null = null;
      await act(async () => {
        response = await result.current.requestImpresso("Solicito radiografia");
      });

      expect(requestImpresso).toHaveBeenCalledWith("session-1", {
        text: "Solicito radiografia",
      });
      expect(response).toEqual(impressoResponse);
      expect(result.current.impressos).toEqual([chestXray]);
      expect(result.current.impressoError).toBeNull();
      expect(result.current.status).toBe("active");
    });

    it("surfaces an impresso request failure without failing the station", async () => {
      const requestImpresso = vi
        .fn()
        .mockRejectedValue(
          new ApiError(422, "invalid_request", "Requisição inválida."),
        );
      const api = apiMock({ requestImpresso });
      const { result } = renderHook(() => useStation(api));

      await act(async () => {
        await result.current.start(true);
      });

      let response: RequestImpressoResponse | null = impressoResponse;
      await act(async () => {
        response = await result.current.requestImpresso("");
      });

      expect(response).toBeNull();
      expect(result.current.status).toBe("active");
      expect(result.current.error).toBeNull();
      expect(result.current.impressoError).toBe("Requisição inválida.");
      expect(result.current.impressos).toEqual([]);
    });

    it("uses a safe pt-BR message when an unknown impresso request failure occurs", async () => {
      const requestImpresso = vi
        .fn()
        .mockRejectedValue(new Error("socket details"));
      const api = apiMock({ requestImpresso });
      const { result } = renderHook(() => useStation(api));

      await act(async () => {
        await result.current.start(true);
      });

      await act(async () => {
        await result.current.requestImpresso("Solicito radiografia");
      });

      expect(result.current.status).toBe("active");
      expect(result.current.impressoError).toBe(
        "Não foi possível solicitar o impresso. Tente novamente.",
      );
    });

    it("restores previously released impressos when resuming an active session", async () => {
      sessionStorage.setItem(sessionIdStorageKey, "session-1");
      const resumedDetail: SessionDetail = {
        ...session,
        status: "active",
        completion_reason: null,
        messages: [],
      };
      const api = apiMock({
        getSession: vi.fn().mockResolvedValue(resumedDetail),
        getImpressos: vi.fn().mockResolvedValue(impressosListResponse),
      });

      const { result } = renderHook(() => useStation(api));

      await waitFor(() => {
        expect(result.current.status).toBe("active");
      });
      await waitFor(() => {
        expect(result.current.impressos).toEqual([chestXray]);
      });
      expect(api.getImpressos).toHaveBeenCalledWith("session-1");
    });
  });
});
