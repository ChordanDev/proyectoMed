import { useCallback, useEffect, useRef, useState } from "react";
import { Room, RoomEvent, Track } from "livekit-client";
import { ApiError, type VoiceSession } from "../api/client";

export type VoiceSessionStatus =
  | "idle"
  | "requesting"
  | "connecting"
  | "connected"
  | "reconnecting"
  | "disconnected"
  | "failed";

export interface VoiceSessionError {
  code: string;
  message: string;
}

export interface VoiceSessionApi {
  createVoiceSession: (sessionId: string) => Promise<VoiceSession>;
}

/** Minimal subset of livekit-client's Track used by the hook, so tests can
 * inject a fake track without depending on the real class hierarchy. */
export interface VoiceTrack {
  kind: Track.Kind;
  attach(element: HTMLMediaElement): HTMLMediaElement;
  detach(element?: HTMLMediaElement): HTMLMediaElement | HTMLMediaElement[];
}

/** Minimal subset of livekit-client's Room used by the hook, so tests can
 * inject a fake room without opening a real WebRTC connection. */
export interface VoiceRoom {
  localParticipant: {
    setMicrophoneEnabled(enabled: boolean): Promise<unknown>;
  };
  connect(url: string, token: string): Promise<void>;
  disconnect(): Promise<void>;
  on(event: string, listener: (...args: unknown[]) => void): unknown;
  off(event: string, listener: (...args: unknown[]) => void): unknown;
}

export interface UseVoiceSessionOptions {
  api: VoiceSessionApi;
  sessionId: string | null;
  active: boolean;
  createRoom?: () => VoiceRoom;
}

const defaultCreateRoom = (): VoiceRoom =>
  new Room({
    adaptiveStream: false,
    dynacast: false,
    disconnectOnPageLeave: true,
  });

const genericErrorMessage =
  "A conexão de voz falhou. Você pode tentar novamente.";
const microphoneDeniedMessage =
  "Permissão de microfone negada. Autorize o microfone e tente novamente.";

const isPermissionDenied = (cause: unknown): boolean =>
  cause instanceof Error &&
  (cause.name === "NotAllowedError" || cause.name === "PermissionDeniedError");

const describeFailure = (cause: unknown): VoiceSessionError => {
  if (cause instanceof ApiError) {
    return { code: cause.code, message: cause.message };
  }
  if (isPermissionDenied(cause)) {
    return { code: "microphone_denied", message: microphoneDeniedMessage };
  }
  return { code: "media_error", message: genericErrorMessage };
};

const idleStatuses = new Set<VoiceSessionStatus>([
  "idle",
  "disconnected",
  "failed",
]);

export const useVoiceSession = ({
  api,
  sessionId,
  active,
  createRoom = defaultCreateRoom,
}: UseVoiceSessionOptions) => {
  const [status, setStatus] = useState<VoiceSessionStatus>("idle");
  const [error, setError] = useState<VoiceSessionError | null>(null);
  const statusRef = useRef<VoiceSessionStatus>("idle");
  const generationRef = useRef(0);
  const roomRef = useRef<VoiceRoom | null>(null);
  const audioElementRef = useRef<HTMLAudioElement | null>(null);
  const patientTrackRef = useRef<VoiceTrack | null>(null);

  const setStatusSafe = useCallback((next: VoiceSessionStatus) => {
    statusRef.current = next;
    setStatus(next);
  }, []);

  const detachPatientTrack = useCallback(() => {
    patientTrackRef.current?.detach();
    patientTrackRef.current = null;
  }, []);

  const attachAudioElement = useCallback((element: HTMLAudioElement | null) => {
    audioElementRef.current = element;
    if (element && patientTrackRef.current) {
      patientTrackRef.current.attach(element);
    }
  }, []);

  const teardownRoom = useCallback(
    (room: VoiceRoom) => {
      room.off(RoomEvent.TrackSubscribed, onTrackSubscribed.current);
      room.off(RoomEvent.TrackUnsubscribed, onTrackUnsubscribed.current);
      room.off(RoomEvent.Reconnecting, onReconnecting.current);
      room.off(RoomEvent.Reconnected, onReconnected.current);
      room.off(RoomEvent.Disconnected, onDisconnected.current);
      void room.disconnect();
    },
    [],
  );

  // Stable listener refs so on/off pair with the exact same function identity.
  const onTrackSubscribed = useRef((..._args: unknown[]) => {});
  const onTrackUnsubscribed = useRef((..._args: unknown[]) => {});
  const onReconnecting = useRef((..._args: unknown[]) => {});
  const onReconnected = useRef((..._args: unknown[]) => {});
  const onDisconnected = useRef((..._args: unknown[]) => {});

  const disconnect = useCallback(() => {
    generationRef.current += 1;
    const room = roomRef.current;
    roomRef.current = null;
    detachPatientTrack();
    if (room) {
      teardownRoom(room);
    }
    if (statusRef.current !== "idle") {
      setStatusSafe("disconnected");
    }
  }, [detachPatientTrack, setStatusSafe, teardownRoom]);

  const connect = useCallback(async (): Promise<void> => {
    if (!sessionId || !idleStatuses.has(statusRef.current)) return;

    const generation = ++generationRef.current;
    setError(null);
    setStatusSafe("requesting");

    let session: VoiceSession;
    try {
      session = await api.createVoiceSession(sessionId);
    } catch (cause) {
      if (generationRef.current !== generation) return;
      setError(describeFailure(cause));
      setStatusSafe("failed");
      return;
    }

    if (generationRef.current !== generation) return;

    const room = createRoom();

    onTrackSubscribed.current = (...args: unknown[]) => {
      if (generationRef.current !== generation) return;
      const [track] = args as unknown as [VoiceTrack, unknown, unknown];
      if (track.kind !== Track.Kind.Audio) return;
      if (patientTrackRef.current && patientTrackRef.current !== track) {
        patientTrackRef.current.detach();
      }
      patientTrackRef.current = track;
      if (audioElementRef.current) {
        track.attach(audioElementRef.current);
      }
    };
    onTrackUnsubscribed.current = (...args: unknown[]) => {
      if (generationRef.current !== generation) return;
      const [track] = args as unknown as [VoiceTrack, unknown, unknown];
      if (patientTrackRef.current === track) {
        detachPatientTrack();
      }
    };
    onReconnecting.current = () => {
      if (generationRef.current !== generation) return;
      setStatusSafe("reconnecting");
    };
    onReconnected.current = () => {
      if (generationRef.current !== generation) return;
      setStatusSafe("connected");
    };
    onDisconnected.current = () => {
      if (generationRef.current !== generation) return;
      roomRef.current = null;
      detachPatientTrack();
      setStatusSafe("disconnected");
    };

    room.on(RoomEvent.TrackSubscribed, onTrackSubscribed.current);
    room.on(RoomEvent.TrackUnsubscribed, onTrackUnsubscribed.current);
    room.on(RoomEvent.Reconnecting, onReconnecting.current);
    room.on(RoomEvent.Reconnected, onReconnected.current);
    room.on(RoomEvent.Disconnected, onDisconnected.current);

    setStatusSafe("connecting");

    try {
      await room.connect(session.url, session.token);
    } catch (cause) {
      if (generationRef.current !== generation) {
        teardownRoom(room);
        return;
      }
      setError(describeFailure(cause));
      setStatusSafe("failed");
      teardownRoom(room);
      return;
    }

    if (generationRef.current !== generation) {
      teardownRoom(room);
      return;
    }

    try {
      await room.localParticipant.setMicrophoneEnabled(true);
    } catch (cause) {
      if (generationRef.current !== generation) {
        teardownRoom(room);
        return;
      }
      setError(describeFailure(cause));
      setStatusSafe("failed");
      teardownRoom(room);
      return;
    }

    if (generationRef.current !== generation) {
      teardownRoom(room);
      return;
    }

    roomRef.current = room;
    setStatusSafe("connected");
  }, [
    api,
    createRoom,
    detachPatientTrack,
    sessionId,
    setStatusSafe,
    teardownRoom,
  ]);

  useEffect(() => {
    if (!active) disconnect();
  }, [active, disconnect]);

  useEffect(() => () => disconnect(), [disconnect]);

  return {
    status,
    error,
    connect,
    disconnect,
    attachAudioElement,
  };
};
