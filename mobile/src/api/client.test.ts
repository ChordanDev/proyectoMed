import { describe, expect, it, jest } from "@jest/globals";
import { createApiClient } from "./client";

const baseUrl = "https://api.example.test";
const jsonResponse = (body: unknown, status = 200) =>
  ({
    ok: status >= 200 && status < 300,
    status,
    json: async () => body,
  }) as Response;

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
      server_now: "2026-01-01T10:00:00Z",
    };
    const reply = {
      reply_text: "A dor começou há duas horas.",
      reply_audio_url: null,
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
    const fetchMock = jest
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

    expect(fetchMock.mock.calls).toEqual([
      [`${baseUrl}/api/stations/active`, { method: "GET" }],
      [
        `${baseUrl}/api/stations/active/sessions`,
        expect.objectContaining({
          method: "POST",
          body: JSON.stringify({ audio_consent: true }),
        }),
      ],
      [
        `${baseUrl}/api/stations/active/sessions/session%2F1/messages`,
        expect.objectContaining({
          method: "POST",
          body: JSON.stringify(message),
        }),
      ],
      [
        `${baseUrl}/api/stations/active/sessions/session-1/finish`,
        expect.objectContaining({
          method: "POST",
          body: JSON.stringify({ reason: "timer" }),
        }),
      ],
      [
        `${baseUrl}/api/stations/active/sessions/session-1/result`,
        { method: "GET" },
      ],
    ]);
  });

  it("decodes API failures into ApiError", async () => {
    const fetchMock = jest
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
});
