import { expect, test } from "./fixtures";
import {
  LEARNER_QUESTION,
  PATIENT_REPLY,
  answeredTurn,
  enterStation,
  expectInvalidatedAttempt,
  persistedSessionId,
  restartStation,
  sendText,
} from "./station";

// The session TTL is fixed at creation and never renewed: it must outlast the
// steps a test takes before its deliberate wait (a text turn, and for the
// second attempt the notice and brief screens too), even on a loaded runner.
const SESSION_TTL_MS = 15_000;

test.use({ harnessOptions: { conversationTimeoutMs: SESSION_TTL_MS } });

test("an expired session invalidates the attempt and a restart recovers", async ({
  page,
  stack,
}) => {
  await enterStation(page);
  const sessionId = await persistedSessionId(page);
  await answeredTurn(page);

  await page.waitForTimeout(SESSION_TTL_MS + 500);
  await sendText(page, LEARNER_QUESTION);

  await expectInvalidatedAttempt(page);
  await restartStation(page, stack, sessionId!);

  // A fresh attempt works within its own TTL.
  await enterStation(page);
  await sendText(page, LEARNER_QUESTION);
  await expect(page.getByTestId("message-patient")).toHaveText(
    new RegExp(PATIENT_REPLY),
  );
});
