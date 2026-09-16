import { act, renderHook } from "@testing-library/react-native";
import {
  ApiError,
  type CompletedSession,
  type MessageReply,
  type Session,
  type SessionResult,
} from "../api/client";
import { useStation, type StationApi } from "./useStation";

const session: Session = {
  session_id: "session-1",
  station_id: "station-1",
  station_version: "1.0.0",
  audio_consent: true,
  started_at: "2026-01-01T10:00:00Z",
  expires_at: "2026-01-01T10:30:00Z",
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
  startSession: jest.fn().mockResolvedValue(session),
  sendMessage: jest.fn().mockResolvedValue(reply),
  finishSession: jest.fn().mockResolvedValue(completed),
  fetchResult: jest.fn().mockResolvedValue(stationResult),
  ...overrides,
});

describe("useStation", () => {
  it("owns one complete station session from loading through its result", async () => {
    const pendingStart = deferred<Session>();
    const pendingFinish = deferred<CompletedSession>();
    const pendingResult = deferred<SessionResult>();
    const api = apiMock({
      startSession: jest.fn(() => pendingStart.promise),
      finishSession: jest.fn(() => pendingFinish.promise),
      fetchResult: jest.fn(() => pendingResult.promise),
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
      startSession: jest.fn(() => pendingStart.promise),
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
    const startSession = jest
      .fn<
        ReturnType<StationApi["startSession"]>,
        Parameters<StationApi["startSession"]>
      >()
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

  it("ignores a late send failure after the session finishes", async () => {
    const pendingSend = deferred<MessageReply>();
    const api = apiMock({
      sendMessage: jest.fn(() => pendingSend.promise),
    });
    const { result } = await renderHook(() => useStation(api));

    await act(async () => {
      await result.current.start(true);
    });

    let sendPromise!: Promise<MessageReply | null>;
    await act(() => {
      sendPromise = result.current.send(message);
    });
    expect(api.sendMessage).toHaveBeenCalledTimes(1);

    await act(async () => {
      await result.current.finish("user");
    });
    expect(result.current).toMatchObject({
      status: "finished",
      result: stationResult,
      error: null,
    });

    let receivedReply: MessageReply | null = reply;
    await act(async () => {
      pendingSend.reject(new Error("late socket failure"));
      receivedReply = await sendPromise;
    });

    expect(receivedReply).toBeNull();
    expect(result.current).toMatchObject({
      status: "finished",
      result: stationResult,
      error: null,
    });
  });

  it("ignores a late send success after the session finishes", async () => {
    const pendingSend = deferred<MessageReply>();
    const api = apiMock({
      sendMessage: jest.fn(() => pendingSend.promise),
    });
    const { result } = await renderHook(() => useStation(api));

    await act(async () => {
      await result.current.start(true);
    });

    let sendPromise!: Promise<MessageReply | null>;
    await act(() => {
      sendPromise = result.current.send(message);
    });
    await act(async () => {
      await result.current.finish("user");
    });

    let receivedReply: MessageReply | null = null;
    await act(async () => {
      pendingSend.resolve(reply);
      receivedReply = await sendPromise;
    });

    expect(receivedReply).toBeNull();
    expect(result.current).toMatchObject({
      status: "finished",
      result: stationResult,
      error: null,
    });
  });

  it("uses a safe pt-BR message when an unknown API failure occurs", async () => {
    const api = apiMock({
      sendMessage: jest.fn().mockRejectedValue(new Error("socket details")),
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
});
