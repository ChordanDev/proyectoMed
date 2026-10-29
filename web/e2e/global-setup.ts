import { compileBackend } from "../src/integration/harness";

// The worker fixtures boot Phoenix under MIX_ENV=dev; compiling once here keeps
// a cold build out of every per-file startup timeout.
export default async function globalSetup(): Promise<void> {
  await compileBackend();
}
