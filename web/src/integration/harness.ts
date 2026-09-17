import { spawn, type ChildProcess } from "node:child_process";
import http from "node:http";
import net from "node:net";
import path from "node:path";
import { fileURLToPath } from "node:url";

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const BACKEND_DIR = path.resolve(__dirname, "../../../backend");

export interface E2EHarnessOptions {
  mockOpenAIReplies?: string[];
  startupTimeoutMs?: number;
}

export interface E2EHarnessInstance {
  baseUrl: string;
  port: number;
  mockOpenAIPort: number;
  stop: () => Promise<void>;
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

export async function startE2EHarness(
  options: E2EHarnessOptions = {},
): Promise<E2EHarnessInstance> {
  const {
    mockOpenAIReplies = ["A dor começou durante uma caminhada."],
    startupTimeoutMs = 25_000,
  } = options;

  let replyIndex = 0;

  // 1. Start Mock OpenAI server
  const mockServer = http.createServer((req, res) => {
    let _body = "";
    req.on("data", (chunk: Buffer) => {
      _body += chunk.toString();
    });
    req.on("end", () => {
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

  const mockPort = await getAvailablePort();
  await new Promise<void>((resolve, reject) => {
    mockServer.on("error", reject);
    mockServer.listen(mockPort, "127.0.0.1", () => resolve());
  });

  // 2. Select free port for Phoenix
  const phxPort = await getAvailablePort();

  // 3. Spawn Phoenix process with env overrides
  const phxProcess: ChildProcess = spawn("mix", ["phx.server"], {
    cwd: BACKEND_DIR,
    env: {
      ...process.env,
      PORT: String(phxPort),
      PHX_SERVER: "true",
      OPENAI_API_KEY: "e2e-stub-key",
      OPENAI_BASE_URL: `http://127.0.0.1:${mockPort}/v1`,
      MIX_ENV: "dev",
    },
    stdio: ["ignore", "pipe", "pipe"],
  });

  let processOutput = "";
  phxProcess.stdout?.on("data", (data: Buffer) => {
    processOutput += data.toString();
  });
  phxProcess.stderr?.on("data", (data: Buffer) => {
    processOutput += data.toString();
  });

  // 4. Poll health endpoint until ready
  const startTime = Date.now();
  let isHealthy = false;
  const baseUrl = `http://127.0.0.1:${phxPort}`;

  while (Date.now() - startTime < startupTimeoutMs) {
    if (phxProcess.exitCode !== null) {
      break;
    }
    try {
      const res = await fetch(`${baseUrl}/`);
      if (res.ok) {
        const data = (await res.json()) as { status?: string };
        if (data.status === "ok") {
          isHealthy = true;
          break;
        }
      }
    } catch {
      // Endpoint not accepting connections yet
    }
    await new Promise((resolve) => setTimeout(resolve, 200));
  }

  if (!isHealthy) {
    phxProcess.kill("SIGKILL");
    await new Promise<void>((resolve) => mockServer.close(() => resolve()));
    throw new Error(
      `Phoenix failed to start within ${startupTimeoutMs}ms on port ${phxPort}.\nProcess output:\n${processOutput}`,
    );
  }

  const stop = async () => {
    await new Promise<void>((resolve) => {
      if (phxProcess.exitCode !== null) {
        resolve();
        return;
      }
      phxProcess.once("exit", () => resolve());
      phxProcess.kill("SIGTERM");

      setTimeout(() => {
        if (phxProcess.exitCode === null) {
          phxProcess.kill("SIGKILL");
        }
      }, 5000);
    });

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
