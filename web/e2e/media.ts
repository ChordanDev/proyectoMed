// Chromium media switches. The fake device is a synthetic microphone (a tone)
// instead of real hardware. Headless Chromium has no permission prompt to
// answer: without the fake UI switch every microphone request fails with
// NotSupportedError, whatever the context permissions say, so the switch
// decides the outcome instead.
const FAKE_MICROPHONE = "--use-fake-device-for-media-stream";

/** The learner allows the microphone. */
export const MICROPHONE_GRANTED_ARGS = [
  FAKE_MICROPHONE,
  "--use-fake-ui-for-media-stream",
];

/** The learner refuses the microphone: getUserMedia rejects with NotAllowedError. */
export const MICROPHONE_DENIED_ARGS = [
  FAKE_MICROPHONE,
  "--use-fake-ui-for-media-stream=deny",
];
