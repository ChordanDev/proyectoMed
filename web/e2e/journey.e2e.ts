import { expect, test } from "./fixtures";
import {
  LEARNER_QUESTION,
  PATIENT_REPLY,
  answeredTurn,
  countdown,
  enterStation,
  expectInvalidatedAttempt,
  expectNoStaleOutput,
  expectSessionGone,
  persistedSessionId,
  remainingSeconds,
  restartStation,
  sendText,
  strings,
} from "./station";

const STATION_SECONDS = 10 * 60;

test.describe("learner journey", () => {
  test("notice → start → text turn → manual finish → result → discard", async ({
    page,
    stack,
  }) => {
    await enterStation(page);

    // The countdown starts from the server's 10-minute deadline and runs down.
    const startSeconds = await remainingSeconds(page);
    expect(startSeconds).toBeLessThanOrEqual(STATION_SECONDS);
    expect(startSeconds).toBeGreaterThan(STATION_SECONDS - 15);
    await expect
      .poll(() => remainingSeconds(page))
      .toBeLessThan(startSeconds);

    const sessionId = await persistedSessionId(page);
    expect(sessionId).toBeTruthy();

    await sendText(page, LEARNER_QUESTION);
    await expect(page.getByTestId("message-learner")).toHaveText(
      new RegExp(LEARNER_QUESTION),
    );
    await expect(page.getByTestId("message-patient")).toHaveText(
      new RegExp(PATIENT_REPLY),
    );

    await page.getByRole("button", { name: strings.finishStation }).click();
    await expect(
      page.getByRole("heading", { name: strings.resultReportTitle }),
    ).toBeVisible({ timeout: 30_000 });
    await expect(
      page.getByRole("heading", { name: strings.resultCoverage }),
    ).toBeVisible();
    await expect(page.getByText(strings.resultSessionOnly)).toBeVisible();

    await restartStation(page, stack, sessionId!);

    // A new attempt starts clean: fresh session, fresh countdown, empty transcript.
    await enterStation(page);
    const nextSessionId = await persistedSessionId(page);
    expect(nextSessionId).toBeTruthy();
    expect(nextSessionId).not.toBe(sessionId);
    expect(await remainingSeconds(page)).toBeGreaterThan(STATION_SECONDS - 15);
    await expect(page.getByTestId("message-learner")).toHaveCount(0);
    await expectNoStaleOutput(page);
  });

  test("the countdown follows the server clock, not the device clock", async ({
    page,
  }) => {
    // A device clock an hour ahead must neither shorten nor end the station.
    await page.clock.setFixedTime(new Date(Date.now() + 60 * 60 * 1000));
    await enterStation(page);

    const startSeconds = await remainingSeconds(page);
    expect(startSeconds).toBeGreaterThan(STATION_SECONDS - 15);
    await expect
      .poll(() => remainingSeconds(page))
      .toBeLessThan(startSeconds);
    await expect(page.getByTestId("station-screen")).toBeVisible();
  });

  test("a network failure invalidates the attempt without partial feedback", async ({
    page,
    stack,
  }) => {
    await enterStation(page);
    const sessionId = await persistedSessionId(page);
    await answeredTurn(page);

    await page.route("**/api/stations/active/sessions/*/messages", (route) =>
      route.abort("connectionreset"),
    );
    await sendText(page, LEARNER_QUESTION);

    await expectInvalidatedAttempt(page);
    await expect(countdown(page)).toHaveCount(0);

    await page.unroute("**/api/stations/active/sessions/*/messages");
    await restartStation(page, stack, sessionId!);
  });

  test("a session the server lost invalidates the attempt", async ({
    page,
    stack,
  }) => {
    await enterStation(page);
    const sessionId = await persistedSessionId(page);
    await answeredTurn(page);

    // The server drops the session behind the learner's back (a restart or a
    // purge): the next turn finds no session.
    await stack.api.discardSession(sessionId!);
    await sendText(page, LEARNER_QUESTION);

    await expectInvalidatedAttempt(page);
    await restartStation(page, stack, sessionId!);
  });

  test("leaving the page cancels the attempt and discards its data", async ({
    page,
    stack,
  }) => {
    await enterStation(page);
    const sessionId = await persistedSessionId(page);
    await sendText(page, LEARNER_QUESTION);
    await expect(page.getByTestId("message-patient")).toHaveText(
      new RegExp(PATIENT_REPLY),
    );

    // pagehide sends a keepalive discard.
    await page.goto("about:blank");
    await expectSessionGone(stack, sessionId!);

    await page.goto("/");
    await expect(
      page.getByRole("heading", { name: strings.noticeTitle }),
    ).toBeVisible();
    await expectNoStaleOutput(page);
    expect(await persistedSessionId(page)).toBeNull();
  });
});
