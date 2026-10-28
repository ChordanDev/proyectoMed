import { test as base } from "@playwright/test";
import path from "node:path";
import { fileURLToPath } from "node:url";
import { createServer, type ViteDevServer } from "vite";
import {
  startE2EHarness,
  type E2EHarnessInstance,
  type E2EHarnessOptions,
} from "../src/integration/harness";

const WEB_DIR = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..");

export interface StationStack {
  /** The Vite SPA, which proxies `/api` to this stack's Phoenix. */
  appUrl: string;
  harness: E2EHarnessInstance;
  /** Direct Phoenix calls, for checks and actions the learner cannot make. */
  api: StationApi;
}

export interface StationApi {
  /** The HTTP status and error code of reading the session (200 and null when it exists). */
  readSession: (sessionId: string) => Promise<{ status: number; code: string | null }>;
  discardSession: (sessionId: string) => Promise<void>;
}

// The SPA's own client reads Vite's `import.meta.env`, so the Node side of the
// suite talks to Phoenix through this minimal client instead.
function stationApi(baseUrl: string): StationApi {
  const sessionUrl = (sessionId: string) =>
    `${baseUrl}/api/stations/active/sessions/${encodeURIComponent(sessionId)}`;
  return {
    readSession: async (sessionId) => {
      const response = await fetch(sessionUrl(sessionId));
      if (response.ok) return { status: response.status, code: null };
      const body = (await response.json().catch(() => null)) as {
        error?: unknown;
      } | null;
      const code = typeof body?.error === "string" ? body.error : null;
      return { status: response.status, code };
    },
    discardSession: async (sessionId) => {
      const response = await fetch(`${sessionUrl(sessionId)}/discard`, {
        method: "POST",
      });
      if (!response.ok) {
        throw new Error(`Discard of ${sessionId} failed with ${response.status}`);
      }
    },
  };
}

interface WorkerFixtures {
  /** Provider doubles and backend settings for every test in the file. */
  harnessOptions: E2EHarnessOptions;
  stack: StationStack;
}

async function startSpa(apiUrl: string): Promise<ViteDevServer> {
  const server = await createServer({
    root: WEB_DIR,
    configFile: path.join(WEB_DIR, "vite.config.ts"),
    clearScreen: false,
    logLevel: "warn",
    server: {
      host: "127.0.0.1",
      port: 0,
      proxy: { "/api": apiUrl },
    },
  });
  await server.listen();
  return server;
}

export const test = base.extend<object, WorkerFixtures>({
  harnessOptions: [{}, { option: true, scope: "worker" }],

  stack: [
    async ({ harnessOptions }, use) => {
      const harness = await startE2EHarness({
        voiceMode: "turn",
        startupTimeoutMs: 45_000,
        ...harnessOptions,
      });
      let spa: ViteDevServer | undefined;
      try {
        spa = await startSpa(harness.baseUrl);
        const appUrl = spa.resolvedUrls?.local[0];
        if (!appUrl) throw new Error("Vite did not report a local URL");
        await use({
          appUrl,
          harness,
          api: stationApi(harness.baseUrl),
        });
      } finally {
        await spa?.close();
        await harness.stop();
      }
    },
    { scope: "worker", timeout: 120_000 },
  ],

  baseURL: async ({ stack }, use) => {
    await use(stack.appUrl);
  },
});

export { expect } from "@playwright/test";
