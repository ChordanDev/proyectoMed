import {
  ActiveStationResponse,
  StartSessionRequest,
  StartSessionResponse,
  SendMessageRequest,
  SendMessageResponse,
  TranscribeResponse,
  SynthesizeRequest,
  SynthesizeResponse,
  FinishSessionRequest,
  FinishSessionResponse,
  ResultResponse,
  ApiError,
} from "../../src/api/types";

describe("Station API Contract Types (#42)", () => {
  it("models active station response", () => {
    const active: ActiveStationResponse = {
      station_id: "chest-pain-initial-assessment",
      version: "1.0.0",
      display_title: "Avaliação inicial de dor torácica",
      language: "pt-BR",
    };
    expect(active.station_id).toBe("chest-pain-initial-assessment");
  });

  it("models start session request and response with session identity", () => {
    const request: StartSessionRequest = {
      audio_consent: true,
    };

    const response: StartSessionResponse = {
      session_id: "123e4567-e89b-12d3-a456-426614174000",
      station_id: "chest-pain-initial-assessment",
      station_version: "1.0.0",
      audio_consent: true,
      started_at: "2026-09-02T16:00:00Z",
      expires_at: "2026-09-02T16:30:00Z",
      server_now: "2026-09-02T16:00:00Z",
    };

    expect(request.audio_consent).toBe(true);
    expect(response.station_id).toBe("chest-pain-initial-assessment");
    expect(response.station_version).toBe("1.0.0");
    expect(response.audio_consent).toBe(true);
  });

  it("models conversation message request and response", () => {
    const request: SendMessageRequest = {
      role: "learner",
      modality: "text",
      text: "O que está sentindo?",
    };

    const response: SendMessageResponse = {
      reply_text: "Dor no peito.",
      reply_audio_url: null,
      server_now: "2026-09-02T16:01:00Z",
    };

    expect(request.role).toBe("learner");
    expect(response.reply_text).toBe("Dor no peito.");
  });

  it("models transcribe and synthesize contracts using synthesized_at only when needed", () => {
    const transcribe: TranscribeResponse = {
      text: "Bom dia",
      duration_seconds: 1.2,
      transcribed_at: "2026-09-02T16:01:00Z",
    };

    const synthesizeReq: SynthesizeRequest = {
      text: "Dor no peito.",
      voice: "nova",
    };

    const synthesizeResp: SynthesizeResponse = {
      format: "mp3",
      synthesized_at: "2026-09-02T16:01:05Z",
    };

    expect(transcribe.transcribed_at).toBeDefined();
    expect(synthesizeReq.voice).toBe("nova");
    expect(synthesizeResp.synthesized_at).toBe("2026-09-02T16:01:05Z");
  });

  it("models finish and result contracts without global score", () => {
    const finishReq: FinishSessionRequest = {
      reason: "user",
    };

    const finishResp: FinishSessionResponse = {
      session_id: "123",
      status: "completed",
      completed_at: "2026-09-02T16:10:00Z",
    };

    const resultResp: ResultResponse = {
      session_id: "123",
      status: "completed",
      criteria: [
        {
          id: "cardiac-history",
          status: "met",
          evidence: ["Investigou características da dor."],
          recommendation: "",
        },
      ],
    };

    expect(finishReq.reason).toBe("user");
    expect(finishResp.status).toBe("completed");
    expect(resultResp.criteria[0].status).toBe("met");
  });

  it("models canonical error response", () => {
    const error: ApiError = {
      error: "session_expired",
      message: "A sessão expirou.",
    };
    expect(error.error).toBe("session_expired");
  });
});
