import { act, renderHook } from "@testing-library/react";
import { RoomEvent, Track } from "livekit-client";
import { ApiError, type VoiceSession } from "../api/client";
import {
  useVoiceSession,
  type VoiceSessionApi,
  type VoiceRoom,
} from "./useVoiceSession";

const voiceSession: VoiceSession = {
  url: "wss://livekit.example.test",
  token: "signed-jwt",
  room: "station-session-session-1",
  identity: "learner-session-1",
  expires_at: "2026-01-01T10:02:00Z",
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

class FakeRoom implements VoiceRoom {
  listeners = new Map<string, Set<(...args: unknown[]) => void>>();
  connectCalls: Array<{ url: string; token: string }> = [];
  disconnectCalls = 0;
  micCalls: boolean[] = [];
  connectImpl: () => Promise<void> = () => Promise.resolve();
  micImpl: () => Promise<unknown> = () => Promise.resolve(undefined);

  localParticipant = {
    setMicrophoneEnabled: (enabled: boolean) => {
      this.micCalls.push(enabled);
      return this.micImpl();
    },
  };

  on(event: string, listener: (...args: unknown[]) => void): this {
    if (!this.listeners.has(event)) this.listeners.set(event, new Set());
    this.listeners.get(event)!.add(listener);
    return this;
  }

  off(event: string, listener: (...args: unknown[]) => void): this {
    this.listeners.get(event)?.delete(listener);
    return this;
  }

  emit(event: string, ...args: unknown[]): void {
    this.listeners.get(event)?.forEach((listener) => listener(...args));
  }

  connect(url: string, token: string): Promise<void> {
    this.connectCalls.push({ url, token });
    return this.connectImpl();
  }

  disconnect(): Promise<void> {
    this.disconnectCalls += 1;
    // Mirror the real livekit-client Room: disconnect() asynchronously emits
    // RoomEvent.Disconnected to whatever listeners are still registered.
    this.emit(RoomEvent.Disconnected, "CLIENT_INITIATED");
    return Promise.resolve();
  }
}

const fakeAudioTrack = () => ({
  kind: Track.Kind.Audio,
  attach: vi.fn((el: HTMLMediaElement) => el),
  detach: vi.fn(() => []),
});

describe("useVoiceSession", () => {
  it("connects through requesting, connecting, connected", async () => {
    const room = new FakeRoom();
    const pendingCreate = deferred<VoiceSession>();
    const pendingRoomConnect = deferred<void>();
    room.connectImpl = () => pendingRoomConnect.promise;
    const api: VoiceSessionApi = {
      createVoiceSession: vi.fn(() => pendingCreate.promise),
    };
    const createRoom = vi.fn(() => room);
    const { result } = await renderHook(() =>
      useVoiceSession({ api, sessionId: "session-1", active: true, createRoom }),
    );

    expect(result.current.status).toBe("idle");

    let connectPromise!: Promise<void>;
    act(() => {
      connectPromise = result.current.connect();
    });
    expect(result.current.status).toBe("requesting");

    await act(async () => {
      pendingCreate.resolve(voiceSession);
      await Promise.resolve();
      await Promise.resolve();
    });
    expect(result.current.status).toBe("connecting");
    expect(room.connectCalls).toEqual([
      { url: voiceSession.url, token: voiceSession.token },
    ]);

    await act(async () => {
      pendingRoomConnect.resolve();
      await connectPromise;
    });
    expect(result.current.status).toBe("connected");
    expect(room.micCalls).toEqual([true]);
  });

  it("publishes exactly one microphone track and no other kind", async () => {
    const room = new FakeRoom();
    const api: VoiceSessionApi = {
      createVoiceSession: vi.fn().mockResolvedValue(voiceSession),
    };
    const { result } = await renderHook(() =>
      useVoiceSession({
        api,
        sessionId: "session-1",
        active: true,
        createRoom: () => room,
      }),
    );

    await act(async () => {
      await result.current.connect();
    });

    expect(room.micCalls).toEqual([true]);
    expect(result.current.status).toBe("connected");
  });

  it("attaches and detaches a single patient audio track", async () => {
    const room = new FakeRoom();
    const { result } = await renderHook(() =>
      useVoiceSession({
        api: { createVoiceSession: vi.fn().mockResolvedValue(voiceSession) },
        sessionId: "session-1",
        active: true,
        createRoom: () => room,
      }),
    );

    await act(async () => {
      await result.current.connect();
    });

    const element = document.createElement("audio");
    act(() => {
      result.current.attachAudioElement(element);
    });

    const track = fakeAudioTrack();
    act(() => {
      room.emit(RoomEvent.TrackSubscribed, track, {}, {});
    });
    expect(track.attach).toHaveBeenCalledWith(element);

    act(() => {
      room.emit(RoomEvent.TrackUnsubscribed, track, {}, {});
    });
    expect(track.detach).toHaveBeenCalled();
  });

  it("ignores a non-audio track", async () => {
    const room = new FakeRoom();
    const { result } = await renderHook(() =>
      useVoiceSession({
        api: { createVoiceSession: vi.fn().mockResolvedValue(voiceSession) },
        sessionId: "session-1",
        active: true,
        createRoom: () => room,
      }),
    );

    await act(async () => {
      await result.current.connect();
    });

    const element = document.createElement("audio");
    act(() => {
      result.current.attachAudioElement(element);
    });

    const videoTrack = { kind: Track.Kind.Video, attach: vi.fn(), detach: vi.fn() };
    act(() => {
      room.emit(RoomEvent.TrackSubscribed, videoTrack, {}, {});
    });
    expect(videoTrack.attach).not.toHaveBeenCalled();
  });

  it("maps microphone permission denial to microphone_denied", async () => {
    const room = new FakeRoom();
    room.micImpl = () => {
      const error = new Error("denied");
      error.name = "NotAllowedError";
      return Promise.reject(error);
    };
    const { result } = await renderHook(() =>
      useVoiceSession({
        api: { createVoiceSession: vi.fn().mockResolvedValue(voiceSession) },
        sessionId: "session-1",
        active: true,
        createRoom: () => room,
      }),
    );

    await act(async () => {
      await result.current.connect();
    });

    expect(result.current.status).toBe("failed");
    expect(result.current.error?.code).toBe("microphone_denied");
    expect(room.disconnectCalls).toBe(1);
  });

  it.each([
    ["403", "audio_consent_required"],
    ["429", "rate_limited"],
    ["503", "voice_unavailable"],
  ])("maps API error %s to failed with code %s", async (_label, code) => {
    const api: VoiceSessionApi = {
      createVoiceSession: vi
        .fn()
        .mockRejectedValue(new ApiError(Number(_label), code, "erro")),
    };
    const { result } = await renderHook(() =>
      useVoiceSession({
        api,
        sessionId: "session-1",
        active: true,
        createRoom: () => new FakeRoom(),
      }),
    );

    await act(async () => {
      await result.current.connect();
    });

    expect(result.current.status).toBe("failed");
    expect(result.current.error).toEqual({ code, message: "erro" });
  });

  it("maps a generic connection failure to media_error", async () => {
    const room = new FakeRoom();
    room.connectImpl = () => Promise.reject(new Error("ws closed"));
    const { result } = await renderHook(() =>
      useVoiceSession({
        api: { createVoiceSession: vi.fn().mockResolvedValue(voiceSession) },
        sessionId: "session-1",
        active: true,
        createRoom: () => room,
      }),
    );

    await act(async () => {
      await result.current.connect();
    });

    expect(result.current.status).toBe("failed");
    expect(result.current.error?.code).toBe("media_error");
  });

  it("moves through reconnecting back to connected on room events", async () => {
    const room = new FakeRoom();
    const { result } = await renderHook(() =>
      useVoiceSession({
        api: { createVoiceSession: vi.fn().mockResolvedValue(voiceSession) },
        sessionId: "session-1",
        active: true,
        createRoom: () => room,
      }),
    );

    await act(async () => {
      await result.current.connect();
    });
    expect(result.current.status).toBe("connected");

    act(() => {
      room.emit(RoomEvent.Reconnecting);
    });
    expect(result.current.status).toBe("reconnecting");

    act(() => {
      room.emit(RoomEvent.Reconnected);
    });
    expect(result.current.status).toBe("connected");

    act(() => {
      room.emit(RoomEvent.Disconnected, "SERVER_SHUTDOWN");
    });
    expect(result.current.status).toBe("disconnected");
  });

  it("does not connect a late-resolving room when disconnect happens first", async () => {
    const room = new FakeRoom();
    const pendingConnect = deferred<void>();
    room.connectImpl = () => pendingConnect.promise;
    const { result } = await renderHook(() =>
      useVoiceSession({
        api: { createVoiceSession: vi.fn().mockResolvedValue(voiceSession) },
        sessionId: "session-1",
        active: true,
        createRoom: () => room,
      }),
    );

    let connectPromise!: Promise<void>;
    await act(async () => {
      connectPromise = result.current.connect();
      await Promise.resolve();
      await Promise.resolve();
    });
    expect(room.connectCalls).toHaveLength(1);

    act(() => {
      result.current.disconnect();
    });
    expect(result.current.status).toBe("disconnected");

    await act(async () => {
      pendingConnect.resolve();
      await connectPromise;
    });

    expect(room.disconnectCalls).toBe(1);
    expect(room.micCalls).toEqual([]);
    expect(result.current.status).toBe("disconnected");
  });

  it("does not connect when disconnect happens while the token request is in flight", async () => {
    const pendingCreate = deferred<VoiceSession>();
    const createRoom = vi.fn();
    const { result } = await renderHook(() =>
      useVoiceSession({
        api: { createVoiceSession: vi.fn(() => pendingCreate.promise) },
        sessionId: "session-1",
        active: true,
        createRoom,
      }),
    );

    let connectPromise!: Promise<void>;
    act(() => {
      connectPromise = result.current.connect();
    });
    expect(result.current.status).toBe("requesting");

    act(() => {
      result.current.disconnect();
    });

    await act(async () => {
      pendingCreate.resolve(voiceSession);
      await connectPromise;
    });

    expect(createRoom).not.toHaveBeenCalled();
    expect(result.current.status).toBe("disconnected");
  });

  it("is idempotent when disconnected repeatedly", async () => {
    const room = new FakeRoom();
    const { result } = await renderHook(() =>
      useVoiceSession({
        api: { createVoiceSession: vi.fn().mockResolvedValue(voiceSession) },
        sessionId: "session-1",
        active: true,
        createRoom: () => room,
      }),
    );

    await act(async () => {
      await result.current.connect();
    });

    act(() => {
      result.current.disconnect();
      result.current.disconnect();
    });

    expect(room.disconnectCalls).toBe(1);
    expect(result.current.status).toBe("disconnected");
  });

  it("disconnects automatically on unmount", async () => {
    const room = new FakeRoom();
    const { result, unmount } = await renderHook(() =>
      useVoiceSession({
        api: { createVoiceSession: vi.fn().mockResolvedValue(voiceSession) },
        sessionId: "session-1",
        active: true,
        createRoom: () => room,
      }),
    );

    await act(async () => {
      await result.current.connect();
    });

    unmount();
    expect(room.disconnectCalls).toBe(1);
  });

  it("disconnects automatically when active turns false", async () => {
    const room = new FakeRoom();
    const { result, rerender } = await renderHook(
      ({ active }: { active: boolean }) =>
        useVoiceSession({
          api: { createVoiceSession: vi.fn().mockResolvedValue(voiceSession) },
          sessionId: "session-1",
          active,
          createRoom: () => room,
        }),
      { initialProps: { active: true } },
    );

    await act(async () => {
      await result.current.connect();
    });
    expect(result.current.status).toBe("connected");

    await act(async () => {
      rerender({ active: false });
    });

    expect(room.disconnectCalls).toBe(1);
    expect(result.current.status).toBe("disconnected");
  });
});
