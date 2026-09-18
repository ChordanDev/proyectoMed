import { defineConfig } from "vitest/config";
import react from "@vitejs/plugin-react";

// https://vitejs.dev/config/
export default defineConfig({
  plugins: [react()],
  server: {
    port: 5173,
    proxy: {
      "/api": "http://localhost:4000",
    },
  },
  test: {
    globals: true,
    environmentMatchGlobs: [
      ["src/integration/**", "node"],
      ["**", "jsdom"],
    ],
    setupFiles: ["./src/test-setup.ts"],
  },
});
