import { describe, expect, it, vi } from "vitest";
import { createApiClient } from "./client";

const baseUrl = "https://api.example.test";
const jsonResponse = (body: unknown, status = 200) =>
  ({
    ok: status >= 200 && status < 300,
    status,
    json: async () => body,
  }) as Response;
const blobResponse = (blob: Blob, status = 200) =>
  ({
    ok: status >= 200 && status < 300,
    status,
    json: async () => {
      throw new Error("not json");
    },
    blob: async () => blob,
  }) as unknown as Response;

describe("station API client", () => {
  it("models every station flow request and decodes its response", async () => {
    const activeStation = {
      station_id: "station-1",
      version: "1.0.0",
      display_title: "Dor torácica",
      language: "pt-BR",
    };
    const session = {
      session_id: "session-1",
      station_id: "station-1",
      station_version: "1.0.0",
      audio_consent: true,
      started_at: "2026-01-01T10:00:00Z",
      expires_at: "2026-01-01T10:30:00Z",
      deadline_at: "2026-01-01T10:10:00Z",
      server_now: "2026-01-01T10:00:00Z",
    };
    const reply = {
      reply_text: "A dor começou há duas horas.",
      server_now: "2026-01-01T10:01:00Z",
    };
    const completed = {
      session_id: "session-1",
      status: "completed",
      completed_at: "2026-01-01T10:10:00Z",
    };
    const result = {
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
    const fetchMock = vi
      .fn<typeof fetch>()
      .mockResolvedValueOnce(jsonResponse(activeStation))
      .mockResolvedValueOnce(jsonResponse(session))
      .mockResolvedValueOnce(jsonResponse(reply))
      .mockResolvedValueOnce(jsonResponse(completed))
      .mockResolvedValueOnce(jsonResponse(result));
    const client = createApiClient({
      baseUrl: `${baseUrl}/`,
      fetch: fetchMock,
    });
    const message = {
      role: "learner" as const,
      modality: "text" as const,
      text: "Quando a dor começou?",
    };

    await expect(client.getActiveStation()).resolves.toEqual(activeStation);
    await expect(client.startSession({ audio_consent: true })).resolves.toEqual(
      session,
    );
    await expect(client.sendMessage("session/1", message)).resolves.toEqual(
      reply,
    );
    await expect(client.finishSession("session-1", "timer")).resolves.toEqual(
      completed,
    );
    await expect(client.fetchResult("session-1")).resolves.toEqual(result);

    const calls = fetchMock.mock.calls;

    expect(calls.map(([url]) => url)).toEqual([
      `${baseUrl}/api/stations/active`,
      `${baseUrl}/api/stations/active/sessions`,
      `${baseUrl}/api/stations/active/sessions/session%2F1/messages`,
      `${baseUrl}/api/stations/active/sessions/session-1/finish`,
      `${baseUrl}/api/stations/active/sessions/session-1/result`,
    ]);
    expect(calls[0][1]).toMatchObject({ method: "GET" });
    expect(calls[1][1]).toMatchObject({
      method: "POST",
      body: JSON.stringify({ audio_consent: true }),
    });
    expect(calls[2][1]).toMatchObject({
      method: "POST",
      body: JSON.stringify(message),
    });
    expect(calls[3][1]).toMatchObject({
      method: "POST",
      body: JSON.stringify({ reason: "timer" }),
    });
    expect(calls[4][1]).toMatchObject({ method: "GET" });
  });

  it("sends audio blob as multipart form data and decodes transcription result", async () => {
    const transcription = {
      text: "Bom dia, o que você está sentindo?",
      duration_seconds: 3.4,
      transcribed_at: "2026-09-02T16:02:10Z",
    };
    const fetchMock = vi
      .fn<typeof fetch>()
      .mockResolvedValueOnce(jsonResponse(transcription));
    const client = createApiClient({ baseUrl, fetch: fetchMock });

    const blob = new Blob(["fake-audio-bytes"], { type: "audio/webm" });
    const result = await client.transcribeAudio("session-1", blob);

    expect(result).toEqual(transcription);
    expect(fetchMock).toHaveBeenCalledTimes(1);

    const [url, init] = fetchMock.mock.calls[0];
    expect(url).toBe(`${baseUrl}/api/stations/active/sessions/session-1/transcribe`);
    expect(init?.method).toBe("POST");
    expect(init?.body).toBeInstanceOf(FormData);

    const formData = init?.body as FormData;
    expect(formData.get("audio")).toBeInstanceOf(Blob);
  });

  it("decodes a session detail, including its transcript, for refresh/reconnect resume", async () => {
    const sessionDetail = {
      session_id: "session-1",
      station_id: "station-1",
      station_version: "1.0.0",
      audio_consent: true,
      started_at: "2026-01-01T10:00:00Z",
      expires_at: "2026-01-01T10:30:00Z",
      deadline_at: "2026-01-01T10:10:00Z",
      status: "active",
      completion_reason: null,
      messages: [
        { role: "learner", modality: "text", text: "Bom dia", at: "2026-01-01T10:00:05Z" },
        { role: "patient", modality: "text", text: "Boa tarde", at: "2026-01-01T10:00:06Z" },
      ],
      server_now: "2026-01-01T10:05:00Z",
    };
    const fetchMock = vi
      .fn<typeof fetch>()
      .mockResolvedValueOnce(jsonResponse(sessionDetail));
    const client = createApiClient({ baseUrl, fetch: fetchMock });

    await expect(client.getSession("session-1")).resolves.toEqual({
      session_id: "session-1",
      station_id: "station-1",
      station_version: "1.0.0",
      audio_consent: true,
      started_at: "2026-01-01T10:00:00Z",
      expires_at: "2026-01-01T10:30:00Z",
      deadline_at: "2026-01-01T10:10:00Z",
      status: "active",
      completion_reason: null,
      messages: [
        { role: "learner", text: "Bom dia" },
        { role: "patient", text: "Boa tarde" },
      ],
      server_now: "2026-01-01T10:05:00Z",
    });
    expect(fetchMock.mock.calls[0][0]).toBe(
      `${baseUrl}/api/stations/active/sessions/session-1`,
    );
  });

  it("posts JSON to synthesize and returns the audio blob", async () => {
    const audioBlob = new Blob(["fake-mp3-bytes"], { type: "audio/mpeg" });
    const fetchMock = vi
      .fn<typeof fetch>()
      .mockResolvedValueOnce(blobResponse(audioBlob));
    const client = createApiClient({ baseUrl, fetch: fetchMock });

    const result = await client.synthesizeSpeech(
      "session-1",
      "A dor começou há duas horas.",
      "alloy",
    );

    expect(result).toBe(audioBlob);
    expect(fetchMock).toHaveBeenCalledTimes(1);

    const [url, init] = fetchMock.mock.calls[0];
    expect(url).toBe(
      `${baseUrl}/api/stations/active/sessions/session-1/synthesize`,
    );
    expect(init?.method).toBe("POST");
    expect(init?.body).toBe(
      JSON.stringify({ text: "A dor começou há duas horas.", voice: "alloy" }),
    );
  });

  it("posts JSON to synthesize without a voice when omitted", async () => {
    const audioBlob = new Blob(["fake-mp3-bytes"], { type: "audio/mpeg" });
    const fetchMock = vi
      .fn<typeof fetch>()
      .mockResolvedValueOnce(blobResponse(audioBlob));
    const client = createApiClient({ baseUrl, fetch: fetchMock });

    await client.synthesizeSpeech("session-1", "Boa tarde.");

    const [, init] = fetchMock.mock.calls[0];
    expect(init?.body).toBe(JSON.stringify({ text: "Boa tarde." }));
  });

  it("decodes synthesize failures into ApiError", async () => {
    const fetchMock = vi
      .fn<typeof fetch>()
      .mockResolvedValue(
        jsonResponse(
          { error: "session_not_found", message: "Sessão não encontrada." },
          404,
        ),
      );
    const client = createApiClient({ baseUrl, fetch: fetchMock });

    await expect(
      client.synthesizeSpeech("missing", "Olá"),
    ).rejects.toMatchObject({
      name: "ApiError",
      status: 404,
      code: "session_not_found",
      message: "Sessão não encontrada.",
    });
  });

  it("decodes API failures into ApiError", async () => {
    const fetchMock = vi
      .fn<typeof fetch>()
      .mockResolvedValue(
        jsonResponse(
          { error: "session_not_found", message: "Sessão não encontrada." },
          404,
        ),
      );
    const client = createApiClient({ baseUrl, fetch: fetchMock });

    await expect(client.fetchResult("missing")).rejects.toMatchObject({
      name: "ApiError",
      status: 404,
      code: "session_not_found",
      message: "Sessão não encontrada.",
    });
  });

  it("cancels a stalled request at the configured deadline", async () => {
    vi.useFakeTimers();
    let signal: AbortSignal | undefined;
    const fetchMock = vi.fn<typeof fetch>().mockImplementation(
      (_input, init) =>
        new Promise<Response>((_resolve, reject) => {
          signal = init?.signal ?? undefined;
          signal?.addEventListener("abort", () => reject(new Error("aborted")));
        }),
    );
    const client = createApiClient({
      baseUrl,
      fetch: fetchMock,
      timeoutMs: 1_000,
    });

    try {
      const pending = client.getActiveStation();
      const rejection = expect(pending).rejects.toMatchObject({
        name: "ApiError",
        status: 0,
        code: "request_timeout",
      });

      await vi.advanceTimersByTimeAsync(1_000);

      expect(signal?.aborted).toBe(true);
      await rejection;
    } finally {
      vi.useRealTimers();
    }
  });
});
