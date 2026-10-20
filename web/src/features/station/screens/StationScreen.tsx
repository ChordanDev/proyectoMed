import React, { useCallback, useEffect, useRef, useState } from "react";
import type {
  CandidateBrief,
  Impresso,
  RequestImpressoResponse,
  SessionMessage,
} from "../api/client";
import {
  isExaminerAcknowledgement,
  isKeptLearnerTurn,
  recoverableTurnNotice,
} from "../hooks/useStation";
import type { VoiceRoom, VoiceSessionApi } from "../hooks/useVoiceSession";
import type { VoiceTranscriptEvent } from "../hooks/voiceTranscriptEvents";
import strings from "../i18n/pt-BR.json";
import { ImpressoContent } from "./ImpressoContent";
import { impressoCategoryLabel } from "./impressoCategory";
import { StationBrief } from "./StationBrief";
import { VoicePanel } from "./VoicePanel";
import {
  addVoiceLearnerTurn,
  dropSupersededVoiceTurns,
  joinVoiceSegments,
  resolveVoiceTurn,
  showVoiceReplySoFar,
  storedReplyFor,
} from "./voiceTranscript";
import "./StationScreen.css";

/**
 * One transcript entry. `examiner` and `notice` entries are display-only: they
 * are built in the browser, never sent to or stored by the server, never carry
 * patient text and never enter the rubric evidence pool. A `notice` says that
 * the patient did not answer a kept learner turn (#274).
 */
export interface DisplayMessage {
  role: "learner" | "patient" | "examiner" | "notice";
  text: string;
  /** Worker turn id of a real-time voice entry (#270); absent for text turns. */
  voiceTurnId?: number;
  /** A streamed voice reply still growing sentence by sentence (#281). */
  voicePartial?: boolean;
}

const roleLabels: Readonly<Record<DisplayMessage["role"], string>> = {
  learner: strings.roleLearner,
  patient: strings.rolePatient,
  examiner: strings.roleExaminer,
  notice: strings.roleNotice,
};

/** The real-time (LiveKit) voice session hosted by the station screen (#270). */
export interface RealtimeVoiceOptions {
  sessionId: string | null;
  api?: VoiceSessionApi;
  createRoom?: () => VoiceRoom;
}

export interface StationScreenProps {
  /** Send a text turn and receive the AI reply text. Returns null on failure. */
  onSend: (text: string) => Promise<string | null>;
  /** Finish the station session. */
  onFinish: () => void | Promise<void>;
  /** Whether the learner granted consent to capture and transcribe audio. */
  audioConsent?: boolean;
  /** Transcribe a captured audio blob. Returns null when voice is unavailable. */
  onTranscribe?: (audioBlob: Blob) => Promise<string | null>;
  /** Send a transcribed voice turn and receive the AI reply text. */
  onSendVoice?: (text: string) => Promise<string | null>;
  /** Synthesize a patient reply into playable audio. Returns null when unavailable. */
  onSynthesize?: (text: string) => Promise<Blob | null>;
  /** Optional station title for the header. */
  title?: string;
  /** Candidate brief the learner can reopen during the station (timer keeps running). */
  brief?: CandidateBrief | null;
  /** External error message to display. */
  error?: string | null;
  /** Whether the send/finish controls are disabled (e.g. finishing in progress). */
  disabled?: boolean;
  /** Milliseconds left until the server-authoritative station deadline, when known. */
  remainingMs?: number | null;
  /** Transcript restored from a resumed session (refresh/reconnect). */
  initialMessages?: DisplayMessage[];
  /** Request an Impresso (physical exam maneuver or complementary exam). Returns null on failure. */
  onRequestImpresso: (text: string) => Promise<RequestImpressoResponse | null>;
  /** Impressos released so far for the session, in release order. */
  impressos?: Impresso[];
  /** Error message from the most recent failed impresso request. */
  impressoError?: string | null;
  /**
   * Real-time voice (VOICE_MODE=realtime, #270): hosts the voice panel and
   * feeds spoken turns into the transcript. The turn-based record and play
   * buttons are not offered while it is set.
   */
  realtimeVoice?: RealtimeVoiceOptions;
  /** Reads the stored session transcript, to show a spoken reply as stored. */
  onFetchTranscript?: () => Promise<SessionMessage[] | null>;
  /**
   * Re-reads the released impressos and returns the newly released ones, after
   * a spoken turn the examiner acknowledged (#302).
   */
  onRefreshImpressos?: () => Promise<Impresso[]>;
}

/** The examiner's display-only hand-over entry, titles only. */
const handOverMessage = (released: Impresso[]): DisplayMessage => ({
  role: "examiner",
  text: `${strings.examinerHandsOver} ${released
    .map((impresso) => impresso.title)
    .join(", ")}`,
});

/** The examiner impressos an acknowledgement released (#302), if any. */
const releasedByAcknowledgement = (cause: unknown): Impresso[] => {
  const released = (cause as { newlyReleased?: unknown }).newlyReleased;
  return Array.isArray(released) ? (released as Impresso[]) : [];
};

const isStationTimeElapsedError = (cause: unknown): boolean =>
  typeof cause === "object" &&
  cause !== null &&
  (cause as { code?: unknown }).code === "station_time_elapsed";

const formatCountdown = (remainingMs: number): string => {
  const totalSeconds = Math.max(0, Math.floor(remainingMs / 1000));
  const minutes = Math.floor(totalSeconds / 60);
  const seconds = totalSeconds % 60;
  return `${String(minutes).padStart(2, "0")}:${String(seconds).padStart(2, "0")}`;
};

export function StationScreen({
  onSend,
  onFinish,
  audioConsent = false,
  onTranscribe,
  onSendVoice,
  onSynthesize,
  title,
  brief = null,
  error = null,
  disabled = false,
  remainingMs = null,
  initialMessages,
  onRequestImpresso,
  impressos = [],
  impressoError = null,
  realtimeVoice,
  onFetchTranscript,
  onRefreshImpressos,
}: StationScreenProps): React.JSX.Element {
  const [messages, setMessages] = useState<DisplayMessage[]>(
    () => initialMessages ?? [],
  );
  const [inputValue, setInputValue] = useState("");
  const [sending, setSending] = useState(false);
  const [recording, setRecording] = useState(false);
  const [transcribing, setTranscribing] = useState(false);
  const [voiceFallback, setVoiceFallback] = useState(false);
  const [sendError, setSendError] = useState<string | null>(null);
  const [turnRetryNotice, setTurnRetryNotice] = useState<string | null>(null);
  const [playingIndex, setPlayingIndex] = useState<number | null>(null);
  const [loadingAudioIndex, setLoadingAudioIndex] = useState<number | null>(
    null,
  );
  const [unavailableAudioIndices, setUnavailableAudioIndices] = useState<
    Set<number>
  >(new Set());
  const [impressoModalOpen, setImpressoModalOpen] = useState(false);
  const [impressoRequestText, setImpressoRequestText] = useState("");
  const [submittingImpresso, setSubmittingImpresso] = useState(false);
  const [impressoFeedback, setImpressoFeedback] = useState<string | null>(
    null,
  );
  const [impressoDrawerOpen, setImpressoDrawerOpen] = useState(false);
  const [briefOpen, setBriefOpen] = useState(false);
  const [selectedImpressoId, setSelectedImpressoId] = useState<string | null>(
    null,
  );
  const messagesEndRef = useRef<HTMLDivElement>(null);
  const recorderRef = useRef<MediaRecorder | null>(null);
  const streamRef = useRef<MediaStream | null>(null);
  const chunksRef = useRef<Blob[]>([]);
  const mountedRef = useRef(true);
  const audioUrlsRef = useRef<Map<number, string>>(new Map());
  const currentAudioRef = useRef<HTMLAudioElement | null>(null);
  const playTokenRef = useRef<object | null>(null);
  // Real-time voice: the live caption is never stored in the transcript.
  const [voiceCaption, setVoiceCaption] = useState<string | null>(null);
  const [voiceNotice, setVoiceNotice] = useState<string | null>(null);
  const voiceLearnerTextsRef = useRef<Map<number, string>>(new Map());
  const voiceResolvingRef = useRef<Set<number>>(new Set());
  const voiceResolvedRef = useRef<Set<number>>(new Set());
  // Sentences of each streamed reply by `segment` index (#281).
  const voiceSegmentsRef = useRef<Map<number, Map<number, string>>>(new Map());
  // The newest voice turn seen: an older streamed turn was superseded (#281).
  const voiceLatestTurnRef = useRef(0);
  // Turns whose reply could not be shown: their learner line stays (#280 C2).
  const voiceUndeliveredRef = useRef<Set<number>>(new Set());
  const realtime = realtimeVoice !== undefined;

  const stopStream = useCallback(() => {
    streamRef.current?.getTracks().forEach((track) => track.stop());
    streamRef.current = null;
  }, []);

  const pauseCurrentAudio = useCallback(() => {
    playTokenRef.current = null;
    currentAudioRef.current?.pause();
    currentAudioRef.current = null;
    if (mountedRef.current) {
      setPlayingIndex(null);
      setLoadingAudioIndex(null);
    }
  }, []);

  const markAudioUnavailable = useCallback((index: number) => {
    setUnavailableAudioIndices((previous) => {
      if (previous.has(index)) return previous;
      const next = new Set(previous);
      next.add(index);
      return next;
    });
  }, []);

  const handlePlay = useCallback(
    async (index: number, text: string) => {
      if (!onSynthesize) return;

      if (playingIndex === index) {
        pauseCurrentAudio();
        return;
      }

      pauseCurrentAudio();
      const token = {};
      playTokenRef.current = token;

      let url = audioUrlsRef.current.get(index);
      if (!url) {
        setLoadingAudioIndex(index);
        let audioBlob: Blob | null;
        try {
          audioBlob = await onSynthesize(text);
        } catch {
          audioBlob = null;
        }

        if (playTokenRef.current !== token) return;

        if (!audioBlob) {
          markAudioUnavailable(index);
          setLoadingAudioIndex(null);
          return;
        }

        url = URL.createObjectURL(audioBlob);
        audioUrlsRef.current.set(index, url);
        setLoadingAudioIndex(null);
      }

      const audio = new Audio(url);
      audio.addEventListener("ended", () => {
        if (playTokenRef.current === token) pauseCurrentAudio();
      });
      audio.addEventListener("error", () => {
        if (playTokenRef.current === token) {
          markAudioUnavailable(index);
          pauseCurrentAudio();
        }
      });

      currentAudioRef.current = audio;
      setPlayingIndex(index);
      try {
        await audio.play();
      } catch {
        if (playTokenRef.current === token) {
          markAudioUnavailable(index);
          pauseCurrentAudio();
        }
      }
    },
    [markAudioUnavailable, onSynthesize, pauseCurrentAudio, playingIndex],
  );

  const enableTextFallback = useCallback(() => {
    recorderRef.current = null;
    chunksRef.current = [];
    stopStream();
    if (mountedRef.current) {
      setRecording(false);
      setTranscribing(false);
      setVoiceFallback(true);
    }
  }, [stopStream]);

  useEffect(() => {
    mountedRef.current = true;
    const audioUrls = audioUrlsRef.current;
    return () => {
      mountedRef.current = false;
      const recorder = recorderRef.current;
      if (recorder && recorder.state !== "inactive") {
        recorder.stop();
      }
      stopStream();
      currentAudioRef.current?.pause();
      currentAudioRef.current = null;
      audioUrls.forEach((url) => URL.revokeObjectURL(url));
      audioUrls.clear();
    };
  }, [stopStream]);

  const browserVoiceSupported =
    typeof MediaRecorder !== "undefined" &&
    typeof navigator.mediaDevices?.getUserMedia === "function";
  const voiceRequested =
    !realtime && audioConsent && Boolean(onTranscribe && onSendVoice);

  useEffect(() => {
    if (voiceRequested && !browserVoiceSupported) {
      enableTextFallback();
    }
  }, [browserVoiceSupported, enableTextFallback, voiceRequested]);

  const scrollToBottom = useCallback(() => {
    if (typeof messagesEndRef.current?.scrollIntoView === "function") {
      messagesEndRef.current.scrollIntoView({ behavior: "smooth" });
    }
  }, []);

  useEffect(() => {
    scrollToBottom();
  }, [messages, sending, scrollToBottom]);

  // An examiner acknowledgement that released impressos the learner asked
  // for (#302): the examiner hands them over and the drawer opens.
  const handOverImpressos = useCallback((released: Impresso[]) => {
    if (released.length === 0 || !mountedRef.current) return;
    setMessages((previous) => [...previous, handOverMessage(released)]);
    setImpressoDrawerOpen(true);
  }, []);

  const sendTurn = useCallback(
    async (
      text: string,
      sender: (message: string) => Promise<string | null>,
    ) => {
      pauseCurrentAudio();
      const learnerMessage: DisplayMessage = { role: "learner", text };
      setMessages((previous) => [...previous, learnerMessage]);
      setSending(true);
      setSendError(null);
      setTurnRetryNotice(null);

      try {
        const replyText = await sender(text);
        if (replyText) {
          setMessages((previous) => [
            ...previous,
            { role: "patient", text: replyText },
          ]);
        } else {
          setSendError(strings.stationError);
        }
      } catch (cause) {
        const retryNotice = recoverableTurnNotice(cause);
        if (isExaminerAcknowledgement(cause)) {
          // The turn was addressed to the examiner (#274): the backend kept it
          // without asking the patient, and the examiner acknowledges it.
          if (mountedRef.current) {
            setMessages((previous) => [
              ...previous,
              { role: "examiner", text: strings.examinerAcknowledgement },
            ]);
            handOverImpressos(releasedByAcknowledgement(cause));
          }
        } else if (isKeptLearnerTurn(cause)) {
          // The patient reply was refused, but the backend kept the learner
          // turn: keep the bubble, leave the input empty and say neutrally
          // that the patient did not answer (#274), never "Anotado.".
          if (mountedRef.current) {
            setMessages((previous) => [
              ...previous,
              { role: "notice", text: strings.patientDidNotAnswerNotice },
            ]);
          }
        } else if (isStationTimeElapsedError(cause)) {
          // The station's deadline elapsed while this turn was in flight:
          // it was never accepted, so it must not linger in the transcript.
          if (mountedRef.current) {
            setMessages((previous) =>
              previous.filter((message) => message !== learnerMessage),
            );
          }
        } else if (retryNotice !== null) {
          // The backend rolled this turn back and the station is still
          // active: drop the learner bubble and hand the text back for a retry.
          if (mountedRef.current) {
            setMessages((previous) =>
              previous.filter((message) => message !== learnerMessage),
            );
            setInputValue(text);
            setTurnRetryNotice(retryNotice);
          }
        } else {
          setSendError(strings.stationError);
        }
      } finally {
        if (mountedRef.current) setSending(false);
      }
    },
    [handOverImpressos, pauseCurrentAudio],
  );

  // Learner voice turns that stay without an outcome: never dropped as barge-in.
  const keptVoiceTurns = useCallback(
    (): ReadonlySet<number> =>
      new Set([...voiceResolvingRef.current, ...voiceUndeliveredRef.current]),
    [],
  );

  // The patient entry shows the stored reply (the full verified text, as on
  // the text path); the spoken text, without stage directions, is the fallback.
  // A streamed reply is resolved only once its turn has ended (#281).
  const resolveVoiceReply = useCallback(
    async (turnId: number, spokenText: string | null) => {
      if (
        voiceResolvingRef.current.has(turnId) ||
        voiceResolvedRef.current.has(turnId)
      ) {
        return;
      }
      voiceResolvingRef.current.add(turnId);
      let replyText: string | null = null;
      try {
        const stored = await onFetchTranscript?.();
        replyText = storedReplyFor(
          stored ?? [],
          voiceLearnerTextsRef.current.get(turnId),
        );
      } catch {
        replyText = null;
      }
      replyText ??= spokenText;
      if (!mountedRef.current) return;
      voiceResolvingRef.current.delete(turnId);
      if (replyText === null) {
        voiceUndeliveredRef.current.add(turnId);
        setVoiceNotice(strings.voiceTextDeliveryFailed);
        return;
      }
      const text = replyText;
      voiceUndeliveredRef.current.delete(turnId);
      voiceResolvedRef.current.add(turnId);
      voiceSegmentsRef.current.delete(turnId);
      setMessages((previous) =>
        resolveVoiceTurn(previous, turnId, { role: "patient", text }, keptVoiceTurns()),
      );
    },
    [keptVoiceTurns, onFetchTranscript],
  );

  const showVoiceSegment = useCallback(
    (turnId: number, segment: number, text: string) => {
      if (
        voiceResolvedRef.current.has(turnId) ||
        turnId < voiceLatestTurnRef.current
      ) {
        return;
      }
      const segments = voiceSegmentsRef.current.get(turnId) ?? new Map();
      segments.set(segment, text);
      voiceSegmentsRef.current.set(turnId, segments);
      const soFar = joinVoiceSegments(segments);
      setMessages((previous) =>
        showVoiceReplySoFar(previous, turnId, soFar, keptVoiceTurns()),
      );
    },
    [keptVoiceTurns],
  );

  // A newer turn supersedes the streamed replies of older unresolved turns:
  // the worker cancelled them, so their end event never comes (#281).
  const supersedeOlderVoiceTurns = useCallback(
    (turnId: number) => {
      if (turnId <= voiceLatestTurnRef.current) return;
      voiceLatestTurnRef.current = turnId;
      const kept = keptVoiceTurns();
      for (const olderTurn of [...voiceSegmentsRef.current.keys()]) {
        if (olderTurn < turnId && !kept.has(olderTurn)) {
          voiceSegmentsRef.current.delete(olderTurn);
        }
      }
      setMessages((previous) => dropSupersededVoiceTurns(previous, turnId, kept));
    },
    [keptVoiceTurns],
  );

  const handleVoiceEvent = useCallback(
    (event: VoiceTranscriptEvent) => {
      if (event.type !== "fatal") supersedeOlderVoiceTurns(event.turnId);
      switch (event.type) {
        case "learner":
          if (!event.final) {
            setVoiceCaption(event.text.trim() || null);
            return;
          }
          setVoiceCaption(null);
          voiceLearnerTextsRef.current.set(event.turnId, event.text);
          setMessages((previous) =>
            addVoiceLearnerTurn(previous, event.turnId, event.text),
          );
          return;
        case "patient":
          setVoiceNotice(null);
          if (event.segment === undefined) {
            void resolveVoiceReply(event.turnId, event.text);
          } else {
            showVoiceSegment(event.turnId, event.segment, event.text);
          }
          return;
        case "patient-complete": {
          const segments = voiceSegmentsRef.current.get(event.turnId);
          void resolveVoiceReply(
            event.turnId,
            segments ? joinVoiceSegments(segments) : null,
          );
          return;
        }
        case "examiner-acknowledged":
        case "patient-unanswered":
          setVoiceNotice(null);
          setMessages((previous) =>
            resolveVoiceTurn(
              previous,
              event.turnId,
              event.type === "examiner-acknowledged"
                ? { role: "examiner", text: strings.examinerAcknowledgement }
                : { role: "notice", text: strings.patientDidNotAnswerNotice },
              keptVoiceTurns(),
            ),
          );
          if (event.type === "examiner-acknowledged" && onRefreshImpressos) {
            void onRefreshImpressos().then(handOverImpressos, () => undefined);
          }
          return;
        case "turn-failure":
          if (event.failure === "text_delivery_failed") {
            // A streamed reply is read once its end event arrives (#281).
            if (!voiceSegmentsRef.current.has(event.turnId)) {
              void resolveVoiceReply(event.turnId, null);
            }
          } else {
            setVoiceNotice(strings.voicePatientAudioFailed);
          }
          return;
        case "fatal":
          setVoiceCaption(null);
          setVoiceNotice(strings.voiceRealtimeStopped);
          return;
      }
    },
    [
      handOverImpressos,
      keptVoiceTurns,
      onRefreshImpressos,
      resolveVoiceReply,
      showVoiceSegment,
      supersedeOlderVoiceTurns,
    ],
  );

  const handleSend = useCallback(async () => {
    const trimmed = inputValue.trim();
    if (!trimmed || sending || transcribing || disabled) return;

    setInputValue("");
    await sendTurn(trimmed, onSend);
  }, [disabled, inputValue, onSend, sendTurn, sending, transcribing]);

  const openImpressoModal = useCallback(() => {
    setImpressoModalOpen(true);
  }, []);

  const closeImpressoModal = useCallback(() => {
    setImpressoModalOpen(false);
  }, []);

  const handleRequestImpresso = useCallback(async () => {
    const trimmed = impressoRequestText.trim();
    if (!trimmed || submittingImpresso) return;

    setSubmittingImpresso(true);
    const response = await onRequestImpresso(trimmed);
    setSubmittingImpresso(false);

    if (response) {
      if (response.decision === "released" && response.newly_released.length > 0) {
        // The examiner hands the impresso over: show it in the transcript as a
        // display-only examiner entry (titles only), next to the drawer.
        const handOver = handOverMessage(response.newly_released);
        setMessages((previous) => [...previous, handOver]);
        setImpressoFeedback(null);
      } else {
        setImpressoFeedback(response.feedback_message);
      }
      setImpressoRequestText("");
      setImpressoModalOpen(false);
    }
  }, [impressoRequestText, onRequestImpresso, submittingImpresso]);

  const toggleImpressoDrawer = useCallback(() => {
    setImpressoDrawerOpen((previous) => !previous);
  }, []);

  const selectedImpresso = impressos.find(
    (impresso) => impresso.id === selectedImpressoId,
  );

  useEffect(() => {
    if (!impressoModalOpen) return;

    const handleKeyDown = (event: KeyboardEvent) => {
      if (event.key === "Escape") closeImpressoModal();
    };

    document.addEventListener("keydown", handleKeyDown);
    return () => document.removeEventListener("keydown", handleKeyDown);
  }, [closeImpressoModal, impressoModalOpen]);

  const startRecording = useCallback(async () => {
    if (
      !voiceRequested ||
      voiceFallback ||
      sending ||
      transcribing ||
      disabled ||
      !browserVoiceSupported
    ) {
      return;
    }

    pauseCurrentAudio();

    try {
      const stream = await navigator.mediaDevices.getUserMedia({ audio: true });
      if (!mountedRef.current) {
        stream.getTracks().forEach((track) => track.stop());
        return;
      }

      const recorder = new MediaRecorder(stream);
      streamRef.current = stream;
      recorderRef.current = recorder;
      chunksRef.current = [];

      recorder.addEventListener("dataavailable", (event: BlobEvent) => {
        if (event.data.size > 0) chunksRef.current.push(event.data);
      });
      recorder.addEventListener("error", enableTextFallback);
      recorder.addEventListener("stop", () => {
        const audioBlob = new Blob(chunksRef.current, {
          type: recorder.mimeType || "audio/webm",
        });
        recorderRef.current = null;
        chunksRef.current = [];
        stopStream();
        if (!mountedRef.current) return;

        setRecording(false);
        setTranscribing(true);
        void (async () => {
          try {
            const text = await onTranscribe?.(audioBlob);
            if (!text) {
              enableTextFallback();
              return;
            }

            setTranscribing(false);
            await sendTurn(text, onSendVoice!);
          } catch {
            enableTextFallback();
          }
        })();
      });

      recorder.start();
      setRecording(true);
    } catch {
      enableTextFallback();
    }
  }, [
    browserVoiceSupported,
    disabled,
    onSendVoice,
    onTranscribe,
    pauseCurrentAudio,
    sendTurn,
    sending,
    stopStream,
    transcribing,
    enableTextFallback,
    voiceFallback,
    voiceRequested,
  ]);

  const stopRecording = useCallback(() => {
    try {
      recorderRef.current?.stop();
    } catch {
      enableTextFallback();
    }
  }, [enableTextFallback]);

  const handleKeyDown = useCallback(
    (event: React.KeyboardEvent<HTMLInputElement>) => {
      if (event.key === "Enter" && !event.shiftKey) {
        event.preventDefault();
        void handleSend();
      }
    },
    [handleSend],
  );

  const busy = sending || transcribing;
  const isSendDisabled = disabled || busy || inputValue.trim().length === 0;
  const displayedError = error || sendError;
  const showVoiceButton =
    voiceRequested && browserVoiceSupported && !voiceFallback;

  return (
    <div className="station-screen" data-testid="station-screen">
      <header className="station-header">
        <h1 className="station-header__title">
          {title ?? strings.stationScreenTitle}
        </h1>
        {remainingMs !== null && (
          <div
            className="station-header__countdown"
            role="timer"
            aria-label={strings.timeRemainingLabel}
            data-testid="station-countdown"
          >
            {formatCountdown(remainingMs)}
          </div>
        )}
        {brief && (
          <button
            type="button"
            className="station-header__brief-button"
            onClick={() => setBriefOpen(true)}
            aria-haspopup="dialog"
            data-testid="brief-open-button"
          >
            {strings.briefOpenButton}
          </button>
        )}
        <button
          type="button"
          className="station-header__finish-button"
          disabled={disabled || sending || recording || transcribing}
          onClick={() => void onFinish()}
          data-testid="finish-button"
        >
          {strings.finishStation}
        </button>
      </header>

      {realtimeVoice && (
        <VoicePanel
          sessionId={realtimeVoice.sessionId}
          active={!disabled}
          api={realtimeVoice.api}
          createRoom={realtimeVoice.createRoom}
          onTranscriptEvent={handleVoiceEvent}
        />
      )}

      <div
        className="station-messages"
        role="log"
        aria-live="polite"
        data-testid="message-list"
      >
        {messages.map((message, index) => {
          const canPlay =
            !realtime &&
            message.role === "patient" &&
            audioConsent &&
            Boolean(onSynthesize) &&
            !unavailableAudioIndices.has(index);
          const isLoadingAudio = loadingAudioIndex === index;
          const isPlaying = playingIndex === index;
          const roleLabel = roleLabels[message.role];
          const isExaminer =
            message.role === "examiner" || message.role === "notice";

          return (
            <div
              key={index}
              className={`station-message station-message--${message.role}`}
              data-testid={`message-${message.role}`}
              role={isExaminer ? "note" : undefined}
              aria-label={isExaminer ? `${roleLabel}: ${message.text}` : undefined}
            >
              <div className="station-message__role">{roleLabel}</div>
              {message.text}
              {canPlay && (
                <button
                  type="button"
                  className="station-message__play-button"
                  disabled={isLoadingAudio}
                  onClick={() => void handlePlay(index, message.text)}
                  data-testid="play-button"
                  aria-label={
                    isLoadingAudio
                      ? strings.loadingAudio
                      : isPlaying
                        ? strings.stopAudio
                        : strings.playAudio
                  }
                >
                  {isLoadingAudio
                    ? strings.loadingAudio
                    : isPlaying
                      ? strings.stopAudio
                      : strings.playAudio}
                </button>
              )}
            </div>
          );
        })}
        <div ref={messagesEndRef} />
      </div>

      {voiceCaption && (
        <div
          className="station-voice-caption"
          aria-label={strings.voiceCaptionLabel}
          data-testid="voice-caption"
        >
          {voiceCaption}
        </div>
      )}

      {busy && (
        <div className="station-typing" role="status" data-testid="typing-indicator">
          {transcribing ? strings.transcribingVoice : strings.sendingMessage}
        </div>
      )}

      {voiceFallback && (
        <div
          className="station-voice-fallback"
          role="status"
          data-testid="voice-fallback"
        >
          {strings.voiceFallbackNotice}
        </div>
      )}

      {voiceNotice && (
        <div
          className="station-voice-fallback"
          role="status"
          data-testid="voice-notice"
        >
          {voiceNotice}
        </div>
      )}

      {displayedError && (
        <div className="station-error" role="alert" data-testid="station-error">
          {displayedError}
        </div>
      )}

      {turnRetryNotice && (
        <div
          className="station-impresso-notice"
          role="status"
          data-testid="turn-retry-notice"
        >
          {turnRetryNotice}
        </div>
      )}

      {impressoFeedback && (
        <div
          className="station-impresso-notice"
          role="status"
          data-testid="impresso-feedback"
        >
          {impressoFeedback}
        </div>
      )}

      <div className="station-input-area">
        <input
          type="text"
          className="station-input-area__input"
          placeholder={strings.inputPlaceholder}
          value={inputValue}
          onChange={(event) => {
            setInputValue(event.target.value);
            setTurnRetryNotice(null);
          }}
          onKeyDown={handleKeyDown}
          disabled={disabled || busy}
          data-testid="message-input"
          aria-label={strings.inputPlaceholder}
        />
        <button
          type="button"
          className="station-input-area__impresso-button"
          disabled={disabled}
          onClick={openImpressoModal}
          data-testid="impresso-request-button"
        >
          {strings.impressoRequestButton}
        </button>
        {showVoiceButton && (
          <button
            type="button"
            className={`station-input-area__voice-button${recording ? " station-input-area__voice-button--recording" : ""}`}
            disabled={disabled || busy}
            onClick={() => void (recording ? stopRecording() : startRecording())}
            data-testid="voice-button"
            aria-label={recording ? strings.stopVoiceInput : strings.startVoiceInput}
          >
            {recording ? strings.stopVoiceInput : strings.startVoiceInput}
          </button>
        )}
        <button
          type="button"
          className="station-input-area__send-button"
          disabled={isSendDisabled}
          onClick={() => void handleSend()}
          data-testid="send-button"
        >
          {sending ? strings.sendingMessage : strings.sendButton}
        </button>
      </div>

      <div className="impresso-drawer" data-testid="impresso-drawer">
        <button
          type="button"
          className="impresso-drawer__toggle"
          onClick={toggleImpressoDrawer}
          aria-expanded={impressoDrawerOpen}
          data-testid="impresso-drawer-toggle"
        >
          {strings.impressoDrawerToggle} ({impressos.length})
        </button>
        {impressoDrawerOpen && (
          <div className="impresso-drawer__content">
            {impressos.length === 0 ? (
              <p>{strings.impressoDrawerEmpty}</p>
            ) : (
              impressos.map((impresso) => {
                const categoryLabel = impressoCategoryLabel(impresso.category);
                return (
                  <button
                    key={impresso.id}
                    type="button"
                    className="impresso-drawer__item"
                    onClick={() => setSelectedImpressoId(impresso.id)}
                    data-testid={`impresso-item-${impresso.id}`}
                  >
                    <span>{impresso.title}</span>
                    {categoryLabel && (
                      <span className="impresso-drawer__category">
                        {categoryLabel}
                      </span>
                    )}
                  </button>
                );
              })
            )}
            {selectedImpresso && (
              <div
                className="impresso-drawer__viewer"
                data-testid="impresso-content"
              >
                <ImpressoContent content={selectedImpresso.content} />
              </div>
            )}
          </div>
        )}
      </div>

      {brief && briefOpen && (
        <div className="impresso-modal-backdrop">
          <div
            className="impresso-modal station-brief-modal"
            role="dialog"
            aria-modal="true"
            aria-labelledby="station-brief-modal-title"
            data-testid="brief-modal"
          >
            <h2 id="station-brief-modal-title">{strings.briefDialogTitle}</h2>
            <StationBrief brief={brief} />
            <div className="impresso-modal__actions">
              <button
                type="button"
                onClick={() => setBriefOpen(false)}
                data-testid="brief-close-button"
              >
                {strings.briefCloseButton}
              </button>
            </div>
          </div>
        </div>
      )}

      {impressoModalOpen && (
        <div className="impresso-modal-backdrop">
          <div
            className="impresso-modal"
            role="dialog"
            aria-modal="true"
            aria-labelledby="impresso-modal-title"
            data-testid="impresso-modal"
          >
            <h2 id="impresso-modal-title">{strings.impressoModalTitle}</h2>
            <label htmlFor="impresso-modal-textarea">
              {strings.impressoModalLabel}
            </label>
            <textarea
              id="impresso-modal-textarea"
              className="impresso-modal__textarea"
              value={impressoRequestText}
              onChange={(event) =>
                setImpressoRequestText(event.target.value)
              }
              data-testid="impresso-modal-textarea"
            />
            {impressoError && (
              <div role="alert" data-testid="impresso-error">
                {impressoError}
              </div>
            )}
            <div className="impresso-modal__actions">
              <button
                type="button"
                onClick={closeImpressoModal}
                data-testid="impresso-modal-cancel"
              >
                {strings.impressoModalCancel}
              </button>
              <button
                type="button"
                disabled={
                  impressoRequestText.trim().length === 0 || submittingImpresso
                }
                onClick={() => void handleRequestImpresso()}
                data-testid="impresso-modal-submit"
              >
                {strings.impressoModalSubmit}
              </button>
            </div>
          </div>
        </div>
      )}
    </div>
  );
}
