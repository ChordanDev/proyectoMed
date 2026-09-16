/**
 * Reconciled Station API Contract types for mobile and backend communication.
 *
 * Implements #42 (child of #28), defining:
 * - Session identity contract (station_id, station_version, audio_consent).
 * - Request and response shapes for every station flow endpoint.
 * - Audio timestamps: `synthesized_at` only when needed; no unneeded timestamps.
 * - Canonical error response shape.
 */

export interface ActiveStationResponse {
 station_id: string;
 version: string;
 display_title: string;
 language: string;
}

export interface StartSessionRequest {
 audio_consent: boolean;
}

export interface StartSessionResponse {
 session_id: string;
 station_id: string;
 station_version: string;
 audio_consent: boolean;
 started_at: string;
 expires_at: string;
 server_now: string;
}

export type MessageRole = "learner";
export type MessageModality = "voice" | "text";

export interface SendMessageRequest {
 role: MessageRole;
 modality: MessageModality;
 text: string;
}

export interface SendMessageResponse {
 reply_text: string;
 reply_audio_url?: string | null;
 server_now: string;
}

export interface TranscribeResponse {
 text: string;
 duration_seconds: number;
 transcribed_at: string;
}

export type VoiceName =
 | "alloy"
 | "echo"
 | "fable"
 | "onyx"
 | "nova"
 | "shimmer";

export interface SynthesizeRequest {
 text: string;
 voice?: VoiceName;
}

export interface SynthesizeResponse {
 audio_binary?: string;
 format?: string;
 synthesized_at?: string;
}

export type FinishReason = "user" | "timer";

export interface FinishSessionRequest {
 reason?: FinishReason;
}

export interface FinishSessionResponse {
 session_id: string;
 status: "completed";
 completed_at: string;
}

export type CriterionStatus = "met" | "omitted" | "uncertain";

export interface CriterionResult {
 id: string;
 status: CriterionStatus;
 evidence: string[];
 recommendation: string;
}

export interface ResultResponse {
 session_id: string;
 status: "completed";
 criteria: CriterionResult[];
}

export interface ApiError {
 error: string;
 message: string;
}
