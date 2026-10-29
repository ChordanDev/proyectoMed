import { defineConfig, devices } from "@playwright/test";
import { MICROPHONE_GRANTED_ARGS } from "./e2e/media";

// Browser E2E suite (#136): real Chromium against the Vite SPA and a local
// Phoenix with deterministic provider doubles. It runs apart from Vitest, ExUnit
// and the HTTP/API harness (`npm run test:e2e`): `npm run test:browser`.
//
// Specs end in `.e2e.ts`, outside Vitest's `*.test.*`/`*.spec.*` include
// patterns, so `vitest run` never picks them up.
export default defineConfig({
  testDir: "./e2e",
  testMatch: "**/*.e2e.ts",
  globalSetup: "./e2e/global-setup.ts",
  // Each spec file boots its own Phoenix and Vite with its own provider doubles
  // (a worker fixture); one worker keeps those stacks from competing for CPU.
  workers: 1,
  fullyParallel: false,
  forbidOnly: Boolean(process.env.CI),
  retries: 0,
  timeout: 60_000,
  expect: { timeout: 10_000 },
  outputDir: "test-results/browser",
  reporter: [
    ["list"],
    ["html", { open: "never", outputFolder: "playwright-report" }],
  ],
  use: {
    trace: "retain-on-failure",
    screenshot: "only-on-failure",
    video: "retain-on-failure",
  },
  projects: [
    {
      name: "chromium",
      use: {
        ...devices["Desktop Chrome"],
        launchOptions: { args: MICROPHONE_GRANTED_ARGS },
      },
    },
  ],
});
