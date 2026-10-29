# Browser E2E and the human smoke checkpoint

Issue #136. The learner journey is verified in a real browser in two layers:

1. **Automated** (`npm --prefix web run test:browser`): Playwright drives
   Chromium through the Vite SPA against a local Phoenix, with deterministic
   provider doubles and a synthetic microphone. No production credential is
   needed. See "Test" in the root `README.md` for prerequisites and what it
   covers.
2. **Human smoke checkpoint** (this page): what a fake microphone and a mocked
   provider cannot prove. Run it before a release that touches the station
   screens, voice, or the station lifecycle, and record the result.

## What the automated suite covers

Each spec file boots its own Phoenix (`MIX_ENV=dev`, the E2E-only approving Jev
adapter) and Vite, with the provider doubles it needs:

| Spec | Provider doubles and settings | Scenarios |
|---|---|---|
| `journey.e2e.ts` | Fixed patient reply | Notice → brief → station → text turn → manual finish → result → discard, then a clean second attempt; countdown driven by the server clock even with the device clock an hour ahead; a network failure and a session the server lost both invalidate the attempt with no partial feedback; leaving the page discards the session |
| `voice.e2e.ts` | Fixed transcription, silent MP3 speech | Microphone granted: record → transcribe → patient reply → playback starts and ends |
| `microphone-denied.e2e.ts` | Chromium denies the microphone | Fallback notice, text keeps working |
| `voice-failures.e2e.ts` | Transcription and speech fail with 500 | Failed transcription falls back to text; failed patient audio removes the play control and keeps the reply readable |
| `timer.e2e.ts` | `E2E_STATION_DURATION_MS=20000` | The countdown reaches zero and the station finishes by timer |
| `expiry.e2e.ts` | `CONVERSATION_TIMEOUT_MS=15000` | An expired session invalidates the attempt; restart recovers |

After every cancellation, invalidation, expiry and discard the suite checks
that no patient output, transcript or result stays on screen, that the
persisted session id is cleared, and that Phoenix no longer serves the session.

On failure Playwright keeps a trace, a screenshot and a video per test under
`web/test-results/browser/`, and an HTML report under
`web/playwright-report/` (`npx --prefix web playwright show-report
web/playwright-report`).

## Human smoke checkpoint

### Prerequisites

- A machine with a real microphone and speakers or headphones.
- The station running locally in turn-based voice (`VOICE_MODE=turn`, the
  default without LiveKit) with a real text provider and a real OpenAI key for
  transcription and speech (`OPENAI_API_KEY`). See "Run" in `README.md`.
- The supported browsers: current Chrome and Edge on desktop. Note any other
  browser you try (Firefox, Safari) as informational.
- A screen reader for the semantics step: VoiceOver on macOS or NVDA on
  Windows.
- Fresh site permissions: remove the microphone permission for
  `http://localhost:5173` before you start.

### Checklist

Mark each item pass or fail. Any fail blocks the release until it is fixed or
accepted in the issue that tracks the release.

**Real microphone path**

- [ ] On the notice, accept the audio consent and enter the station.
- [ ] Press "Usar voz". The browser asks for the microphone; allow it.
- [ ] Ask a question out loud, then press "Parar gravação". "Transcrevendo
      áudio..." shows, your question appears as your turn with your words, and
      the patient answers in text.

**Patient-audio playback**

- [ ] Press "Ouvir resposta" on the patient reply. The voice is audible and
      matches the text. The button reads "Parar áudio" while it plays and
      "Ouvir resposta" again when it ends.

**Interruption to silence**

- [ ] Play a reply and press "Parar áudio" mid-sentence: the audio stops at
      once.
- [ ] Play a reply and press "Usar voz" mid-sentence: the audio stops at once
      and recording starts.
- [ ] Play a reply and press "Finalizar estação": no audio continues on the
      result screen.

**Keyboard navigation**

- [ ] Without the mouse: Tab reaches the consent checkbox (Space toggles it)
      and "Entendi" (Enter activates it), then "Entrar na estação".
- [ ] In the station, Tab reaches "Cenário e tarefas", "Finalizar estação", the
      message box, "Exame Físico / Exames", "Usar voz" and "Enviar", in a
      sensible order, each with a visible focus ring.
- [ ] Enter in the message box sends the message.
- [ ] Escape closes the "Exame Físico / Exames" dialog, and focus returns to
      the station.
- [ ] On the result screen, Tab reaches "Reiniciar estação".

**Screen-reader semantics**

- [ ] The countdown is announced as a timer named "Tempo restante para
      finalizar a estação".
- [ ] The transcript is announced as a log; each turn is read with its role
      ("Você", "Paciente", "Examinador").
- [ ] "Voz indisponível — usando texto." and other status notices are
      announced without moving focus.
- [ ] An invalidated attempt is announced as an alert with the restart
      button.

**Supported-browser permission behavior** (repeat in each supported browser)

- [ ] First request, allowed: recording starts (covered above).
- [ ] First request, blocked: "Voz indisponível — usando texto." shows and the
      text box keeps working.
- [ ] Permission revoked in the site settings while the station is open: the
      next "Usar voz" falls back to text without an error page.

### Record

Add one line per run to the release issue:

```
Browser smoke <date> — <browser + version>, <OS>, <screen reader>: <pass | fail: items>
```
