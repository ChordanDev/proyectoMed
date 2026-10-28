import { spawn, type ChildProcess } from "node:child_process";
import http from "node:http";
import net from "node:net";
import path from "node:path";
import { fileURLToPath } from "node:url";

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const BACKEND_DIR = path.resolve(__dirname, "../../../backend");
const MAX_PROCESS_LOG_BYTES = 64 * 1024; // 64 KB rolling tail
const MAX_MOCK_BODY_BYTES = 64 * 1024; // 64 KB cap for mock request payload
// Recorded learner audio is larger than a chat request: a few seconds of opus.
const MAX_MOCK_AUDIO_BODY_BYTES = 2 * 1024 * 1024;

const CHAT_COMPLETIONS_PATH = "/v1/chat/completions";
const TRANSCRIPTIONS_PATH = "/v1/audio/transcriptions";
const SPEECH_PATH = "/v1/audio/speech";

export interface E2EHarnessOptions {
  mockOpenAIReplies?: string[];
  mockOpenAIFailureStatus?: number;
  /** Text the mock speech-to-text provider returns for every recording. */
  mockTranscriptionText?: string;
  mockTranscriptionFailureStatus?: number;
  mockSpeechFailureStatus?: number;
  conversationTimeoutMs?: number;
  /** Station duration (E2E_STATION_DURATION_MS); the backend default is 10 minutes. */
  stationDurationMs?: number;
  /** VOICE_MODE; unset keeps the backend's own resolution from the environment. */
  voiceMode?: "realtime" | "turn" | "off";
  startupTimeoutMs?: number;
}

export interface E2EHarnessInstance {
  baseUrl: string;
  port: number;
  mockOpenAIPort: number;
  stop: () => Promise<void>;
}

// A child killed by a signal reports exitCode null and only sets signalCode.
function hasExited(child: ChildProcess): boolean {
  return child.exitCode !== null || child.signalCode !== null;
}

async function getAvailablePort(): Promise<number> {
  return new Promise((resolve, reject) => {
    const server = net.createServer();
    server.unref();
    server.on("error", reject);
    server.listen(0, "127.0.0.1", () => {
      const address = server.address();
      if (address && typeof address === "object") {
        const port = address.port;
        server.close(() => resolve(port));
      } else {
        reject(new Error("Unable to determine free port"));
      }
    });
  });
}

// The harness boots Phoenix under MIX_ENV=dev, which `mix test` never compiles.
// Compiling here keeps a cold build out of the startup timeout, so that timeout
// measures server boot only.
export const BACKEND_COMPILE_TIMEOUT_MS = 240_000;

export async function compileBackend(
  timeoutMs: number = BACKEND_COMPILE_TIMEOUT_MS,
): Promise<void> {
  await new Promise<void>((resolve, reject) => {
    const compileProcess = spawn("mix", ["compile"], {
      cwd: BACKEND_DIR,
      env: { ...process.env, MIX_ENV: "dev" },
      stdio: ["ignore", "pipe", "pipe"],
    });

    let compileOutput = "";
    const appendLog = (data: Buffer) => {
      compileOutput += data.toString();
      if (compileOutput.length > MAX_PROCESS_LOG_BYTES) {
        compileOutput = compileOutput.slice(-MAX_PROCESS_LOG_BYTES);
      }
    };
    compileProcess.stdout?.on("data", appendLog);
    compileProcess.stderr?.on("data", appendLog);

    let timedOut = false;
    const killTimer = setTimeout(() => {
      timedOut = true;
      compileProcess.kill("SIGKILL");
    }, timeoutMs);

    compileProcess.once("error", (err) => {
      clearTimeout(killTimer);
      reject(new Error(`Backend compile spawn failed: ${err.message}`));
    });

    compileProcess.once("exit", (code) => {
      clearTimeout(killTimer);
      if (code === 0) {
        resolve();
        return;
      }
      const failureReason = timedOut
        ? `Backend compile did not finish within ${timeoutMs}ms`
        : `Backend compile exited with status ${code}`;
      reject(
        new Error(`${failureReason}.\nProcess output tail:\n${compileOutput}`),
      );
    });
  });
}

// One silent MPEG-1 Layer III frame (128 kbps, 44.1 kHz): a 4-byte header and a
// zeroed body, which decoders play as silence. Enough frames make a short clip
// the browser can decode without a fixture file.
const MP3_FRAME_BYTES = 417;
const MP3_FRAME_HEADER = [0xff, 0xfb, 0x90, 0x64];

export function silentMp3(frames = 40): Buffer {
  const audio = Buffer.alloc(MP3_FRAME_BYTES * frames);
  for (let frame = 0; frame < frames; frame++) {
    audio.set(MP3_FRAME_HEADER, frame * MP3_FRAME_BYTES);
  }
  return audio;
}

function sendProviderFailure(res: http.ServerResponse, status: number): void {
  res.writeHead(status, { "Content-Type": "application/json" });
  res.end(
    JSON.stringify({
      error: {
        message: "Deterministic upstream failure",
        type: "server_error",
      },
    }),
  );
}

export async function startE2EHarness(
  options: E2EHarnessOptions = {},
): Promise<E2EHarnessInstance> {
  const {
    mockOpenAIReplies = ["A dor começou durante uma caminhada."],
    mockOpenAIFailureStatus,
    mockTranscriptionText = "Quando começou a dor no peito?",
    mockTranscriptionFailureStatus,
    mockSpeechFailureStatus,
    conversationTimeoutMs,
    stationDurationMs,
    voiceMode,
    startupTimeoutMs = 25_000,
  } = options;

  let replyIndex = 0;

  // 1. Start Mock OpenAI server listening directly on port 0 (eliminates TOCTOU port race for mock)
  const mockServer = http.createServer((req, res) => {
    // CDD-001: Validate expected method and path from the backend's OpenAI clients
    // (Backend.StationAI.OpenAIAdapter, Backend.Stations.Transcription and TTS).
    const knownPaths = [CHAT_COMPLETIONS_PATH, TRANSCRIPTIONS_PATH, SPEECH_PATH];
    if (req.method !== "POST" || !knownPaths.includes(req.url ?? "")) {
      res.writeHead(404, { "Content-Type": "application/json" });
      res.end(
        JSON.stringify({
          error: {
            message: `Mock OpenAI received unexpected request: ${req.method} ${req.url}. Expected POST ${knownPaths.join(", ")}.`,
            type: "invalid_request_error",
          },
        }),
      );
      return;
    }

    const maxBodyBytes =
      req.url === TRANSCRIPTIONS_PATH
        ? MAX_MOCK_AUDIO_BODY_BYTES
        : MAX_MOCK_BODY_BYTES;
    let bytesReceived = 0;
    let payloadExceeded = false;

    req.on("data", (chunk: Buffer) => {
      bytesReceived += chunk.length;
      if (bytesReceived > maxBodyBytes) {
        payloadExceeded = true;
        req.destroy();
      }
    });

    req.on("end", () => {
      if (payloadExceeded) {
        res.writeHead(413, { "Content-Type": "application/json" });
        res.end(JSON.stringify({ error: { message: "Payload too large" } }));
        return;
      }

      if (req.url === TRANSCRIPTIONS_PATH) {
        if (mockTranscriptionFailureStatus !== undefined) {
          sendProviderFailure(res, mockTranscriptionFailureStatus);
          return;
        }
        res.writeHead(200, { "Content-Type": "application/json" });
        res.end(JSON.stringify({ text: mockTranscriptionText, duration: 1.5 }));
        return;
      }

      if (req.url === SPEECH_PATH) {
        if (mockSpeechFailureStatus !== undefined) {
          sendProviderFailure(res, mockSpeechFailureStatus);
          return;
        }
        res.writeHead(200, { "Content-Type": "audio/mpeg" });
        res.end(silentMp3());
        return;
      }

      if (mockOpenAIFailureStatus !== undefined) {
        sendProviderFailure(res, mockOpenAIFailureStatus);
        return;
      }

      const currentReply =
        mockOpenAIReplies[replyIndex] ??
        mockOpenAIReplies[mockOpenAIReplies.length - 1] ??
        "";
      replyIndex++;

      res.writeHead(200, { "Content-Type": "application/json" });
      res.end(
        JSON.stringify({
          choices: [
            {
              message: {
                role: "assistant",
                content: currentReply,
              },
            },
          ],
        }),
      );
    });
  });

  await new Promise<void>((resolve, reject) => {
    mockServer.once("error", reject);
    mockServer.listen(0, "127.0.0.1", () => resolve());
  });

  const mockAddress = mockServer.address();
  if (!mockAddress || typeof mockAddress !== "object") {
    mockServer.close();
    throw new Error("Unable to determine mock server address");
  }
  const mockPort = mockAddress.port;

  // 2. Select free port for Phoenix
  const phxPort = await getAvailablePort();

  // 3. Spawn Phoenix process with env overrides
  // CDD-001: Set base URL without trailing /v1 because OpenAIAdapter appends /v1/chat/completions
  const phxEnv: NodeJS.ProcessEnv = {
    ...process.env,
    PORT: String(phxPort),
    PHX_SERVER: "true",
    OPENAI_API_KEY: "e2e-stub-key",
    OPENAI_BASE_URL: `http://127.0.0.1:${mockPort}`,
    MIX_ENV: "dev",
    // Jev has no live provider yet and its default adapter fails closed. This
    // selects the E2E-only approving adapter, which exists only in dev/test.
    JEV_E2E_APPROVING_ADAPTER: "true",
  };
  if (conversationTimeoutMs !== undefined) {
    phxEnv.CONVERSATION_TIMEOUT_MS = String(conversationTimeoutMs);
  }
  if (stationDurationMs !== undefined) {
    phxEnv.E2E_STATION_DURATION_MS = String(stationDurationMs);
  }
  if (voiceMode !== undefined) {
    phxEnv.VOICE_MODE = voiceMode;
  }

  let phxProcess: ChildProcess;
  try {
    phxProcess = spawn("mix", ["phx.server"], {
      cwd: BACKEND_DIR,
      env: phxEnv,
      stdio: ["ignore", "pipe", "pipe"],
    });
  } catch (spawnError) {
    mockServer.close();
    throw spawnError;
  }

  // TR-4: Guard against immediate process spawn errors
  let spawnFailedError: Error | null = null;
  phxProcess.once("error", (err) => {
    spawnFailedError = err;
  });

  // SP-113-03: Keep bounded rolling log tail to avoid unbounded memory accumulation
  let processOutput = "";
  const appendLog = (data: Buffer) => {
    processOutput += data.toString();
    if (processOutput.length > MAX_PROCESS_LOG_BYTES) {
      processOutput = processOutput.slice(-MAX_PROCESS_LOG_BYTES);
    }
  };

  phxProcess.stdout?.on("data", appendLog);
  phxProcess.stderr?.on("data", appendLog);

  // 4. Poll health endpoint until ready
  const startTime = Date.now();
  let isHealthy = false;
  const baseUrl = `http://127.0.0.1:${phxPort}`;

  while (Date.now() - startTime < startupTimeoutMs) {
    if (spawnFailedError) {
      break;
    }
    if (hasExited(phxProcess)) {
      break;
    }

    const elapsed = Date.now() - startTime;
    const remaining = Math.max(100, startupTimeoutMs - elapsed);
    const pollTimeoutMs = Math.min(2000, remaining);

    try {
      // TR-2: Pass bounded AbortSignal.timeout to prevent indefinite socket hangs during polling
      const res = await fetch(`${baseUrl}/`, {
        signal: AbortSignal.timeout(pollTimeoutMs),
      });
      if (res.ok) {
        const data = (await res.json()) as { status?: string };
        if (data.status === "ok") {
          isHealthy = true;
          break;
        }
      }
    } catch {
      // Endpoint not accepting connections yet or poll timed out
    }
    await new Promise((resolve) => setTimeout(resolve, 200));
  }

  if (!isHealthy) {
    phxProcess.kill("SIGKILL");
    if ("closeAllConnections" in mockServer && typeof mockServer.closeAllConnections === "function") {
      mockServer.closeAllConnections();
    }
    await new Promise<void>((resolve) => mockServer.close(() => resolve()));

    const failureReason = spawnFailedError
      ? `Process spawn failed: ${(spawnFailedError as Error).message}`
      : `Phoenix failed to start within ${startupTimeoutMs}ms on port ${phxPort}`;

    throw new Error(
      `${failureReason}.\nProcess output tail:\n${processOutput}`,
    );
  }

  const stop = async () => {
    await new Promise<void>((resolve) => {
      if (hasExited(phxProcess)) {
        resolve();
        return;
      }

      let killTimer: ReturnType<typeof setTimeout> | null = null;

      phxProcess.once("exit", () => {
        // TR-3: Clear timeout immediately when child exits cleanly
        if (killTimer) {
          clearTimeout(killTimer);
          killTimer = null;
        }
        resolve();
      });

      phxProcess.kill("SIGTERM");

      // Force kill after 5s if still alive
      killTimer = setTimeout(() => {
        if (!hasExited(phxProcess)) {
          phxProcess.kill("SIGKILL");
        }
      }, 5000);
      killTimer.unref();
    });

    // SP-113-04: Close active/idle connections to prevent hanging open sockets on mock
    if ("closeAllConnections" in mockServer && typeof mockServer.closeAllConnections === "function") {
      mockServer.closeAllConnections();
    }
    await new Promise<void>((resolve) => {
      mockServer.close(() => resolve());
    });
  };

  return {
    baseUrl,
    port: phxPort,
    mockOpenAIPort: mockPort,
    stop,
  };
}
