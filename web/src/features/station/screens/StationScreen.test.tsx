import { render, screen, waitFor } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import { afterEach, describe, expect, it, vi } from "vitest";
import strings from "../i18n/pt-BR.json";
import { StationScreen } from "./StationScreen";

interface FakeRecorderController {
  recorder: FakeMediaRecorder | null;
}

class FakeMediaRecorder {
  readonly mimeType = "audio/webm";
  state: RecordingState = "inactive";
  private listeners = new Map<string, Array<(event: Event) => void>>();

  constructor(_stream: MediaStream, controller: FakeRecorderController) {
    controller.recorder = this;
  }

  addEventListener(type: string, listener: EventListener): void {
    const listeners = this.listeners.get(type) ?? [];
    listeners.push(listener);
    this.listeners.set(type, listeners);
  }

  start(): void {
    this.state = "recording";
  }

  stop(): void {
    this.state = "inactive";
    this.emit("dataavailable", {
      data: new Blob(["recorded audio"], { type: this.mimeType }),
    } as BlobEvent);
    this.emit("stop", new Event("stop"));
  }

  private emit(type: string, event: Event): void {
    this.listeners.get(type)?.forEach((listener) => listener(event));
  }
}

const installVoiceBrowser = ({
  getUserMedia = vi.fn().mockResolvedValue({
    getTracks: () => [{ stop: vi.fn() }],
  }),
  failRecorder = false,
}: {
  getUserMedia?: ReturnType<typeof vi.fn>;
  failRecorder?: boolean;
} = {}) => {
  const controller: FakeRecorderController = { recorder: null };
  vi.stubGlobal("navigator", {
    ...navigator,
    mediaDevices: { getUserMedia },
  });
  vi.stubGlobal(
    "MediaRecorder",
    failRecorder
      ? class {
          constructor() {
            throw new Error("recorder unavailable");
          }
        }
      : class extends FakeMediaRecorder {
          constructor(stream: MediaStream) {
            super(stream, controller);
          }
        },
  );
  return { controller, getUserMedia };
};

afterEach(() => {
  vi.unstubAllGlobals();
});

describe("StationScreen", () => {
  const defaultProps = {
    onSend: vi.fn().mockResolvedValue("reply text"),
    onFinish: vi.fn(),
    onRequestImpresso: vi.fn().mockResolvedValue({
      request_id: "req-1",
      decision: "released",
      released_impressos: [],
      newly_released: [],
      feedback_message: "Impresso liberado.",
    }),
  };

  it("renders the default title and controls", () => {
    render(<StationScreen {...defaultProps} />);

    expect(screen.getByText(strings.stationScreenTitle)).toBeInTheDocument();
    expect(screen.getByTestId("finish-button")).toBeInTheDocument();
    expect(screen.getByTestId("message-input")).toBeInTheDocument();
    expect(screen.getByTestId("send-button")).toBeInTheDocument();
  });

  it("renders a custom title when provided", () => {
    render(<StationScreen {...defaultProps} title="Dor torácica" />);

    expect(screen.getByText("Dor torácica")).toBeInTheDocument();
  });

  it("disables send button when input is empty", () => {
    render(<StationScreen {...defaultProps} />);

    expect(screen.getByTestId("send-button")).toBeDisabled();
  });

  it("enables send button when input has text", async () => {
    const user = userEvent.setup();
    render(<StationScreen {...defaultProps} />);

    await user.type(screen.getByTestId("message-input"), "Olá");

    expect(screen.getByTestId("send-button")).toBeEnabled();
  });

  it("sends a message and displays learner + patient messages", async () => {
    const user = userEvent.setup();
    const onSend = vi.fn().mockResolvedValue("Boa tarde, doutor.");
    render(<StationScreen {...defaultProps} onSend={onSend} />);

    await user.type(screen.getByTestId("message-input"), "Boa tarde");
    await user.click(screen.getByTestId("send-button"));

    // Learner message appears immediately
    expect(screen.getByText("Boa tarde")).toBeInTheDocument();
    expect(screen.getByText(strings.roleLearner)).toBeInTheDocument();

    // onSend called with trimmed text
    expect(onSend).toHaveBeenCalledWith("Boa tarde");

    // Patient reply appears after resolution
    await waitFor(() => {
      expect(screen.getByText("Boa tarde, doutor.")).toBeInTheDocument();
      expect(screen.getByText(strings.rolePatient)).toBeInTheDocument();
    });
  });

  it("clears input after sending", async () => {
    const user = userEvent.setup();
    render(<StationScreen {...defaultProps} />);

    const input = screen.getByTestId("message-input");
    await user.type(input, "Teste");
    await user.click(screen.getByTestId("send-button"));

    expect(input).toHaveValue("");
  });

  it("shows typing indicator while waiting for reply", async () => {
    const user = userEvent.setup();
    let resolve: (value: string | null) => void;
    const onSend = vi.fn(
      () => new Promise<string | null>((r) => { resolve = r; }),
    );
    render(<StationScreen {...defaultProps} onSend={onSend} />);

    await user.type(screen.getByTestId("message-input"), "Olá");
    await user.click(screen.getByTestId("send-button"));

    expect(screen.getByTestId("typing-indicator")).toBeInTheDocument();
    expect(screen.getByTestId("typing-indicator")).toHaveTextContent(
      strings.sendingMessage,
    );

    // Resolve the pending send
    resolve!("Resposta");

    await waitFor(() => {
      expect(screen.queryByTestId("typing-indicator")).not.toBeInTheDocument();
    });
  });

  it("disables input and send while a message is in flight", async () => {
    const user = userEvent.setup();
    let resolve: (value: string | null) => void;
    const onSend = vi.fn(
      () => new Promise<string | null>((r) => { resolve = r; }),
    );
    render(<StationScreen {...defaultProps} onSend={onSend} />);

    await user.type(screen.getByTestId("message-input"), "Olá");
    await user.click(screen.getByTestId("send-button"));

    expect(screen.getByTestId("message-input")).toBeDisabled();
    expect(screen.getByTestId("send-button")).toBeDisabled();

    resolve!("ok");

    await waitFor(() => {
      expect(screen.getByTestId("message-input")).toBeEnabled();
    });
  });

  it("sends on Enter key press", async () => {
    const user = userEvent.setup();
    const onSend = vi.fn().mockResolvedValue("reply");
    render(<StationScreen {...defaultProps} onSend={onSend} />);

    await user.type(screen.getByTestId("message-input"), "Enter test{enter}");

    expect(onSend).toHaveBeenCalledWith("Enter test");
  });

  it("handles null reply (API failure) without crashing and displays recoverable error banner", async () => {
    const user = userEvent.setup();
    const onSend = vi.fn().mockResolvedValue(null);
    render(<StationScreen {...defaultProps} onSend={onSend} />);

    await user.type(screen.getByTestId("message-input"), "Olá");
    await user.click(screen.getByTestId("send-button"));

    // Learner message shown
    await waitFor(() => {
      expect(screen.getByText("Olá")).toBeInTheDocument();
    });

    // No patient message rendered
    expect(screen.queryByTestId("message-patient")).not.toBeInTheDocument();

    // Error banner displayed with stationError message
    expect(screen.getByTestId("station-error")).toBeInTheDocument();
    expect(screen.getByText(strings.stationError)).toBeInTheDocument();

    // Input re-enabled for recovery
    await waitFor(() => {
      expect(screen.getByTestId("message-input")).toBeEnabled();
    });
  });

  it("re-enables input and controls if onSend throws an error and displays error banner", async () => {
    const user = userEvent.setup();
    const onSend = vi.fn().mockRejectedValue(new Error("Network crash"));
    render(<StationScreen {...defaultProps} onSend={onSend} />);

    await user.type(screen.getByTestId("message-input"), "Mensagem com erro");
    await user.click(screen.getByTestId("send-button"));

    await waitFor(() => {
      expect(screen.getByTestId("message-input")).toBeEnabled();
      expect(screen.getByTestId("finish-button")).toBeEnabled();
      expect(screen.queryByTestId("typing-indicator")).not.toBeInTheDocument();
      expect(screen.getByTestId("station-error")).toHaveTextContent(
        strings.stationError,
      );
    });
  });

  it("displays an external error message", () => {
    render(
      <StationScreen {...defaultProps} error="Erro de conexão" />,
    );

    expect(screen.getByTestId("station-error")).toBeInTheDocument();
    expect(screen.getByText("Erro de conexão")).toBeInTheDocument();
  });

  it("calls onFinish when finish button is clicked", async () => {
    const user = userEvent.setup();
    const onFinish = vi.fn();
    render(<StationScreen {...defaultProps} onFinish={onFinish} />);

    await user.click(screen.getByTestId("finish-button"));

    expect(onFinish).toHaveBeenCalledTimes(1);
  });

  it("disables controls when disabled prop is true", () => {
    render(<StationScreen {...defaultProps} disabled />);

    expect(screen.getByTestId("message-input")).toBeDisabled();
    expect(screen.getByTestId("send-button")).toBeDisabled();
    expect(screen.getByTestId("finish-button")).toBeDisabled();
  });

  it("trims whitespace-only input and does not send", async () => {
    const user = userEvent.setup();
    const onSend = vi.fn();
    render(<StationScreen {...defaultProps} onSend={onSend} />);

    await user.type(screen.getByTestId("message-input"), "   ");

    // Send button remains disabled for whitespace-only
    expect(screen.getByTestId("send-button")).toBeDisabled();
  });

  it("does not offer or request voice input without audio consent", () => {
    const { getUserMedia } = installVoiceBrowser();

    render(
      <StationScreen
        {...defaultProps}
        audioConsent={false}
        onTranscribe={vi.fn()}
        onSendVoice={vi.fn()}
      />,
    );

    expect(screen.queryByTestId("voice-button")).not.toBeInTheDocument();
    expect(getUserMedia).not.toHaveBeenCalled();
  });

  it("records, transcribes, and sends a learner voice turn", async () => {
    const user = userEvent.setup();
    installVoiceBrowser();
    const onTranscribe = vi.fn().mockResolvedValue("Como começou a dor?");
    const onSendVoice = vi.fn().mockResolvedValue("Começou há duas horas.");

    render(
      <StationScreen
        {...defaultProps}
        audioConsent
        onTranscribe={onTranscribe}
        onSendVoice={onSendVoice}
      />,
    );

    await user.click(screen.getByTestId("voice-button"));
    await waitFor(() => {
      expect(screen.getByTestId("voice-button")).toHaveAccessibleName(
        strings.stopVoiceInput,
      );
    });
    await user.click(screen.getByTestId("voice-button"));

    await waitFor(() => {
      expect(onTranscribe).toHaveBeenCalledWith(expect.any(Blob));
      expect(onSendVoice).toHaveBeenCalledWith("Como começou a dor?");
      expect(screen.getByText("Como começou a dor?")).toBeInTheDocument();
      expect(screen.getByText("Começou há duas horas.")).toBeInTheDocument();
    });
    expect(screen.queryByTestId("voice-fallback")).not.toBeInTheDocument();
  });

  it("falls back to text for the session when microphone permission is denied", async () => {
    const user = userEvent.setup();
    installVoiceBrowser({
      getUserMedia: vi.fn().mockRejectedValue(new DOMException("denied")),
    });

    render(
      <StationScreen
        {...defaultProps}
        audioConsent
        onTranscribe={vi.fn()}
        onSendVoice={vi.fn()}
      />,
    );

    await user.click(screen.getByTestId("voice-button"));

    await waitFor(() => {
      expect(screen.getByTestId("voice-fallback")).toHaveTextContent(
        strings.voiceFallbackNotice,
      );
    });
    expect(screen.queryByTestId("voice-button")).not.toBeInTheDocument();
    expect(screen.getByTestId("message-input")).toBeEnabled();
  });

  it("falls back to text when MediaRecorder cannot start", async () => {
    const user = userEvent.setup();
    installVoiceBrowser({ failRecorder: true });

    render(
      <StationScreen
        {...defaultProps}
        audioConsent
        onTranscribe={vi.fn()}
        onSendVoice={vi.fn()}
      />,
    );

    await user.click(screen.getByTestId("voice-button"));

    await waitFor(() => {
      expect(screen.getByTestId("voice-fallback")).toHaveTextContent(
        strings.voiceFallbackNotice,
      );
    });
    expect(screen.getByTestId("message-input")).toBeEnabled();
  });

  it("falls back to text when transcription is unavailable", async () => {
    const user = userEvent.setup();
    installVoiceBrowser();
    const onSendVoice = vi.fn();

    render(
      <StationScreen
        {...defaultProps}
        audioConsent
        onTranscribe={vi.fn().mockResolvedValue(null)}
        onSendVoice={onSendVoice}
      />,
    );

    await user.click(screen.getByTestId("voice-button"));
    await waitFor(() => {
      expect(screen.getByTestId("voice-button")).toHaveAccessibleName(
        strings.stopVoiceInput,
      );
    });
    await user.click(screen.getByTestId("voice-button"));

    await waitFor(() => {
      expect(screen.getByTestId("voice-fallback")).toHaveTextContent(
        strings.voiceFallbackNotice,
      );
    });
    expect(onSendVoice).not.toHaveBeenCalled();
    expect(screen.getByTestId("message-input")).toBeEnabled();
  });

  it("renders multiple conversation turns in order", async () => {
    const user = userEvent.setup();
    let callCount = 0;
    const onSend = vi.fn(() => {
      callCount++;
      return Promise.resolve(`Reply ${callCount}`);
    });
    render(<StationScreen {...defaultProps} onSend={onSend} />);

    // First turn
    await user.type(screen.getByTestId("message-input"), "Turn 1");
    await user.click(screen.getByTestId("send-button"));

    await waitFor(() => {
      expect(screen.getByText("Reply 1")).toBeInTheDocument();
    });

    // Second turn
    await user.type(screen.getByTestId("message-input"), "Turn 2");
    await user.click(screen.getByTestId("send-button"));

    await waitFor(() => {
      expect(screen.getByText("Reply 2")).toBeInTheDocument();
    });

    // All messages present in order
    const allMessages = screen.getAllByTestId(/^message-(learner|patient)$/);
    expect(allMessages).toHaveLength(4);
  });

  it("renders the server-authoritative countdown with an accessible timer role", () => {
    render(<StationScreen {...defaultProps} remainingMs={9 * 60 * 1000 + 5_000} />);

    const countdown = screen.getByRole("timer");
    expect(countdown).toHaveTextContent("09:05");
    expect(countdown).toHaveAccessibleName(strings.timeRemainingLabel);
  });

  it("does not render a countdown when remainingMs is not provided", () => {
    render(<StationScreen {...defaultProps} />);

    expect(screen.queryByRole("timer")).not.toBeInTheDocument();
  });

  it("restores a transcript from a resumed session", () => {
    render(
      <StationScreen
        {...defaultProps}
        initialMessages={[
          { role: "learner", text: "Bom dia" },
          { role: "patient", text: "Boa tarde" },
        ]}
      />,
    );

    expect(screen.getByText("Bom dia")).toBeInTheDocument();
    expect(screen.getByText("Boa tarde")).toBeInTheDocument();
  });

  it("removes the learner bubble instead of leaving it as accepted when the send is rejected for station_time_elapsed", async () => {
    const user = userEvent.setup();
    let reject!: (cause: unknown) => void;
    const onSend = vi.fn(
      () =>
        new Promise<string | null>((_resolve, r) => {
          reject = r;
        }),
    );
    render(<StationScreen {...defaultProps} onSend={onSend} />);

    await user.type(screen.getByTestId("message-input"), "Última mensagem");
    await user.click(screen.getByTestId("send-button"));

    // Learner bubble appears immediately, while the turn is in flight.
    expect(screen.getByText("Última mensagem")).toBeInTheDocument();

    reject(
      Object.assign(new Error("O tempo da estação se esgotou."), {
        code: "station_time_elapsed",
      }),
    );

    // ...but is removed once the station_time_elapsed rejection lands.
    await waitFor(() => {
      expect(screen.queryByText("Última mensagem")).not.toBeInTheDocument();
    });
    expect(screen.queryByTestId("station-error")).not.toBeInTheDocument();
  });

  describe("when the patient reply fails verification", () => {
    const verificationRefusal = () =>
      Object.assign(new Error("Não foi possível verificar a resposta."), {
        code: "reply_verification_failed",
      });

    it("removes the learner bubble, restores the draft, and shows an inline notice", async () => {
      const user = userEvent.setup();
      const onSend = vi.fn().mockRejectedValueOnce(verificationRefusal());
      render(<StationScreen {...defaultProps} onSend={onSend} />);

      await user.type(screen.getByTestId("message-input"), "Bom dia, tudo bem?");
      await user.click(screen.getByTestId("send-button"));

      expect(
        await screen.findByTestId("turn-retry-notice"),
      ).toHaveTextContent(strings.replyVerificationFailedNotice);
      expect(strings.replyVerificationFailedNotice).toBe(
        "O paciente não conseguiu responder a essa mensagem. Tente enviar novamente ou reformular a pergunta.",
      );
      expect(screen.queryByText("Bom dia, tudo bem?")).not.toBeInTheDocument();
      expect(screen.getByTestId("message-input")).toHaveValue(
        "Bom dia, tudo bem?",
      );
      expect(screen.queryByTestId("station-error")).not.toBeInTheDocument();
      expect(screen.getByTestId("message-input")).not.toBeDisabled();
    });

    it("clears the notice when the learner edits the draft", async () => {
      const user = userEvent.setup();
      const onSend = vi.fn().mockRejectedValueOnce(verificationRefusal());
      render(<StationScreen {...defaultProps} onSend={onSend} />);

      await user.type(screen.getByTestId("message-input"), "Olá");
      await user.click(screen.getByTestId("send-button"));
      await screen.findByTestId("turn-retry-notice");

      await user.type(screen.getByTestId("message-input"), "!");

      expect(
        screen.queryByTestId("turn-retry-notice"),
      ).not.toBeInTheDocument();
      expect(screen.getByTestId("message-input")).toHaveValue("Olá!");
    });

    it("clears the notice when the retried send succeeds", async () => {
      const user = userEvent.setup();
      const onSend = vi
        .fn()
        .mockRejectedValueOnce(verificationRefusal())
        .mockResolvedValueOnce("Bom dia, doutor.");
      render(<StationScreen {...defaultProps} onSend={onSend} />);

      await user.type(screen.getByTestId("message-input"), "Bom dia");
      await user.click(screen.getByTestId("send-button"));
      await screen.findByTestId("turn-retry-notice");

      await user.click(screen.getByTestId("send-button"));

      expect(await screen.findByText("Bom dia, doutor.")).toBeInTheDocument();
      expect(screen.getByText("Bom dia")).toBeInTheDocument();
      expect(
        screen.queryByTestId("turn-retry-notice"),
      ).not.toBeInTheDocument();
      expect(onSend).toHaveBeenNthCalledWith(2, "Bom dia");
    });
  });

  describe("when the patient reply is refused but the learner turn was kept", () => {
    const keptTurnRefusal = (text: string) =>
      Object.assign(new Error("Não foi possível verificar a resposta."), {
        code: "reply_verification_failed",
        learnerTurn: { role: "learner", text },
      });

    it("keeps the learner bubble, clears the input, and says the message was recorded", async () => {
      const user = userEvent.setup();
      const text = "Na palpação há dor no ponto de McBurney.";
      const onSend = vi.fn().mockRejectedValueOnce(keptTurnRefusal(text));
      render(<StationScreen {...defaultProps} onSend={onSend} />);

      await user.type(screen.getByTestId("message-input"), text);
      await user.click(screen.getByTestId("send-button"));

      expect(
        await screen.findByTestId("turn-retry-notice"),
      ).toHaveTextContent(strings.learnerTurnKeptNotice);
      expect(strings.learnerTurnKeptNotice).toBe(
        "Sua mensagem foi registrada, mas o paciente não respondeu a ela.",
      );
      expect(screen.getByText(text)).toBeInTheDocument();
      expect(screen.getByTestId("message-input")).toHaveValue("");
      expect(screen.queryByTestId("station-error")).not.toBeInTheDocument();
      expect(screen.getByTestId("message-input")).not.toBeDisabled();
    });

    it("sends the next message after the kept turn without resending it", async () => {
      const user = userEvent.setup();
      const onSend = vi
        .fn()
        .mockRejectedValueOnce(keptTurnRefusal("Exame normal."))
        .mockResolvedValueOnce("Entendi, doutor.");
      render(<StationScreen {...defaultProps} onSend={onSend} />);

      await user.type(screen.getByTestId("message-input"), "Exame normal.");
      await user.click(screen.getByTestId("send-button"));
      await screen.findByTestId("turn-retry-notice");

      await user.type(screen.getByTestId("message-input"), "Tem alergias?");
      await user.click(screen.getByTestId("send-button"));

      expect(await screen.findByText("Entendi, doutor.")).toBeInTheDocument();
      expect(screen.getByText("Exame normal.")).toBeInTheDocument();
      expect(screen.getByText("Tem alergias?")).toBeInTheDocument();
      expect(onSend).toHaveBeenNthCalledWith(2, "Tem alergias?");
      expect(
        screen.queryByTestId("turn-retry-notice"),
      ).not.toBeInTheDocument();
    });
  });

  describe.each(["timeout", "station_ai_unavailable"])(
    "when the turn fails with %s",
    (code) => {
      const turnFailure = () =>
        Object.assign(new Error("Falha na resposta do paciente."), { code });

      it("removes the learner bubble, restores the draft, and shows the retry notice", async () => {
        const user = userEvent.setup();
        const onSend = vi.fn().mockRejectedValueOnce(turnFailure());
        render(<StationScreen {...defaultProps} onSend={onSend} />);

        await user.type(
          screen.getByTestId("message-input"),
          "Qual é o seu nome completo?",
        );
        await user.click(screen.getByTestId("send-button"));

        expect(await screen.findByTestId("turn-retry-notice")).toHaveTextContent(
          strings.turnUnavailableNotice,
        );
        expect(strings.turnUnavailableNotice).toBe(
          "Não foi possível obter a resposta agora. Tente enviar novamente.",
        );
        expect(
          screen.queryByText("Qual é o seu nome completo?"),
        ).not.toBeInTheDocument();
        expect(screen.getByTestId("message-input")).toHaveValue(
          "Qual é o seu nome completo?",
        );
        expect(screen.queryByTestId("station-error")).not.toBeInTheDocument();
        expect(screen.getByTestId("message-input")).not.toBeDisabled();
      });

      it("clears the notice when the retried send succeeds", async () => {
        const user = userEvent.setup();
        const onSend = vi
          .fn()
          .mockRejectedValueOnce(turnFailure())
          .mockResolvedValueOnce("Rafael Nogueira, doutor.");
        render(<StationScreen {...defaultProps} onSend={onSend} />);

        await user.type(screen.getByTestId("message-input"), "Seu nome?");
        await user.click(screen.getByTestId("send-button"));
        await screen.findByTestId("turn-retry-notice");

        await user.click(screen.getByTestId("send-button"));

        expect(
          await screen.findByText("Rafael Nogueira, doutor."),
        ).toBeInTheDocument();
        expect(screen.queryByTestId("turn-retry-notice")).not.toBeInTheDocument();
        expect(onSend).toHaveBeenNthCalledWith(2, "Seu nome?");
      });
    },
  );
});

describe("StationScreen playback", () => {
  const installAudio = () => {
    const createObjectURL = vi.fn().mockReturnValue("blob:audio-url");
    const revokeObjectURL = vi.fn();
    URL.createObjectURL = createObjectURL;
    URL.revokeObjectURL = revokeObjectURL;

    const play = vi.fn().mockResolvedValue(undefined);
    const pause = vi.fn();
    vi.stubGlobal(
      "Audio",
      class {
        src: string;
        onended: (() => void) | null = null;
        onerror: (() => void) | null = null;
        constructor(src: string) {
          this.src = src;
        }
        play = play;
        pause = pause;
        addEventListener(type: string, listener: EventListener) {
          if (type === "ended") this.onended = listener as () => void;
          if (type === "error") this.onerror = listener as () => void;
        }
        removeEventListener() {}
      },
    );

    return { createObjectURL, revokeObjectURL, play, pause };
  };

  const defaultProps = {
    onSend: vi.fn().mockResolvedValue("reply text"),
    onFinish: vi.fn(),
    onRequestImpresso: vi.fn().mockResolvedValue({
      request_id: "req-1",
      decision: "released",
      released_impressos: [],
      newly_released: [],
      feedback_message: "Impresso liberado.",
    }),
  };

  const renderWithPatientMessage = async (
    onSynthesize: ReturnType<typeof vi.fn>,
    props: Record<string, unknown> = {},
  ) => {
    const user = userEvent.setup();
    const onSend = vi.fn().mockResolvedValue("Boa tarde, doutor.");
    render(
      <StationScreen
        {...defaultProps}
        onSend={onSend}
        audioConsent
        onSynthesize={onSynthesize}
        {...props}
      />,
    );
    await user.type(screen.getByTestId("message-input"), "Boa tarde");
    await user.click(screen.getByTestId("send-button"));
    await waitFor(() => {
      expect(screen.getByText("Boa tarde, doutor.")).toBeInTheDocument();
    });
    return user;
  };

  it("does not show a play button without audio consent", async () => {
    installAudio();
    const user = userEvent.setup();
    const onSend = vi.fn().mockResolvedValue("Boa tarde, doutor.");
    render(
      <StationScreen
        {...defaultProps}
        onSend={onSend}
        audioConsent={false}
        onSynthesize={vi.fn()}
      />,
    );
    await user.type(screen.getByTestId("message-input"), "Boa tarde");
    await user.click(screen.getByTestId("send-button"));
    await waitFor(() => {
      expect(screen.getByText("Boa tarde, doutor.")).toBeInTheDocument();
    });

    expect(screen.queryByTestId("play-button")).not.toBeInTheDocument();
  });

  it("does not show a play button without onSynthesize", async () => {
    installAudio();
    const user = userEvent.setup();
    const onSend = vi.fn().mockResolvedValue("Boa tarde, doutor.");
    render(<StationScreen {...defaultProps} onSend={onSend} audioConsent />);
    await user.type(screen.getByTestId("message-input"), "Boa tarde");
    await user.click(screen.getByTestId("send-button"));
    await waitFor(() => {
      expect(screen.getByText("Boa tarde, doutor.")).toBeInTheDocument();
    });

    expect(screen.queryByTestId("play-button")).not.toBeInTheDocument();
  });

  it("synthesizes and plays audio when the play button is clicked", async () => {
    const { createObjectURL, play } = installAudio();
    const onSynthesize = vi
      .fn()
      .mockResolvedValue(new Blob(["audio"], { type: "audio/mpeg" }));
    const user = await renderWithPatientMessage(onSynthesize);

    await user.click(screen.getByTestId("play-button"));

    await waitFor(() => {
      expect(onSynthesize).toHaveBeenCalledWith("Boa tarde, doutor.");
      expect(createObjectURL).toHaveBeenCalledTimes(1);
      expect(play).toHaveBeenCalledTimes(1);
      expect(screen.getByTestId("play-button")).toHaveAccessibleName(
        strings.stopAudio,
      );
    });
  });

  it("hides the play button and keeps the text when synthesis returns null, never retrying", async () => {
    installAudio();
    const onSynthesize = vi.fn().mockResolvedValue(null);
    const user = await renderWithPatientMessage(onSynthesize);

    await user.click(screen.getByTestId("play-button"));

    await waitFor(() => {
      expect(screen.queryByTestId("play-button")).not.toBeInTheDocument();
    });
    expect(screen.getByText("Boa tarde, doutor.")).toBeInTheDocument();
    expect(onSynthesize).toHaveBeenCalledTimes(1);
  });

  it("hides the play button when audio.play() rejects, keeping the text", async () => {
    const { play } = installAudio();
    play.mockRejectedValue(new Error("playback blocked"));
    const onSynthesize = vi
      .fn()
      .mockResolvedValue(new Blob(["audio"], { type: "audio/mpeg" }));
    const user = await renderWithPatientMessage(onSynthesize);

    await user.click(screen.getByTestId("play-button"));

    await waitFor(() => {
      expect(screen.queryByTestId("play-button")).not.toBeInTheDocument();
    });
    expect(screen.getByText("Boa tarde, doutor.")).toBeInTheDocument();
  });

  it("pauses playing audio when sending a new turn", async () => {
    const { play, pause } = installAudio();
    const onSynthesize = vi
      .fn()
      .mockResolvedValue(new Blob(["audio"], { type: "audio/mpeg" }));
    const user = await renderWithPatientMessage(onSynthesize);

    await user.click(screen.getByTestId("play-button"));
    await waitFor(() => expect(play).toHaveBeenCalledTimes(1));

    await user.type(screen.getByTestId("message-input"), "Outra pergunta");
    await user.click(screen.getByTestId("send-button"));

    await waitFor(() => expect(pause).toHaveBeenCalledTimes(1));
  });

  it("pauses playing audio when starting a new voice recording", async () => {
    const { play, pause } = installAudio();
    installVoiceBrowser();
    const onSynthesize = vi
      .fn()
      .mockResolvedValue(new Blob(["audio"], { type: "audio/mpeg" }));
    const user = await renderWithPatientMessage(onSynthesize, {
      onTranscribe: vi.fn(),
      onSendVoice: vi.fn(),
    });

    await user.click(screen.getByTestId("play-button"));
    await waitFor(() => expect(play).toHaveBeenCalledTimes(1));

    await user.click(screen.getByTestId("voice-button"));

    await waitFor(() => expect(pause).toHaveBeenCalledTimes(1));
  });
});

describe("StationScreen impresso requests", () => {
  const defaultProps = {
    onSend: vi.fn().mockResolvedValue("reply text"),
    onFinish: vi.fn(),
  };

  const chestXray = {
    id: "chest-xray",
    title: "Radiografia de tórax",
    category: "Exame de imagem",
    content: "Sem sinais de consolidação.",
  };

  it("opens the request modal when the impresso button is clicked", async () => {
    const user = userEvent.setup();
    render(
      <StationScreen
        {...defaultProps}
        onRequestImpresso={vi.fn()}
        impressos={[]}
      />,
    );

    expect(screen.queryByRole("dialog")).not.toBeInTheDocument();

    await user.click(screen.getByTestId("impresso-request-button"));

    const dialog = screen.getByRole("dialog");
    expect(dialog).toHaveAttribute("aria-modal", "true");
    expect(screen.getByLabelText(strings.impressoModalLabel)).toBeInTheDocument();
  });

  it("requests an impresso, shows the feedback message, and closes the modal", async () => {
    const user = userEvent.setup();
    const onRequestImpresso = vi.fn().mockResolvedValue({
      request_id: "req-1",
      decision: "released",
      released_impressos: [chestXray],
      newly_released: [chestXray],
      feedback_message: "Impresso liberado: Radiografia de tórax",
    });
    render(
      <StationScreen
        {...defaultProps}
        onRequestImpresso={onRequestImpresso}
        impressos={[]}
      />,
    );

    await user.click(screen.getByTestId("impresso-request-button"));
    await user.type(
      screen.getByLabelText(strings.impressoModalLabel),
      "Solicito radiografia de tórax",
    );
    await user.click(screen.getByTestId("impresso-modal-submit"));

    expect(onRequestImpresso).toHaveBeenCalledWith(
      "Solicito radiografia de tórax",
    );

    await waitFor(() => {
      expect(screen.queryByRole("dialog")).not.toBeInTheDocument();
    });
    expect(screen.getByTestId("impresso-feedback")).toHaveAttribute(
      "role",
      "status",
    );
    expect(
      screen.getByText("Impresso liberado: Radiografia de tórax"),
    ).toBeInTheDocument();
  });

  it("closes the modal via the cancel button", async () => {
    const user = userEvent.setup();
    render(
      <StationScreen
        {...defaultProps}
        onRequestImpresso={vi.fn()}
        impressos={[]}
      />,
    );

    await user.click(screen.getByTestId("impresso-request-button"));
    await user.click(screen.getByTestId("impresso-modal-cancel"));

    expect(screen.queryByRole("dialog")).not.toBeInTheDocument();
  });

  it("closes the modal on Escape", async () => {
    const user = userEvent.setup();
    render(
      <StationScreen
        {...defaultProps}
        onRequestImpresso={vi.fn()}
        impressos={[]}
      />,
    );

    await user.click(screen.getByTestId("impresso-request-button"));
    expect(screen.getByRole("dialog")).toBeInTheDocument();

    await user.keyboard("{Escape}");

    expect(screen.queryByRole("dialog")).not.toBeInTheDocument();
  });

  it("shows the impressoError prop on failure and keeps the modal open", async () => {
    const user = userEvent.setup();
    const onRequestImpresso = vi.fn().mockResolvedValue(null);
    const { rerender } = render(
      <StationScreen
        {...defaultProps}
        onRequestImpresso={onRequestImpresso}
        impressos={[]}
      />,
    );

    await user.click(screen.getByTestId("impresso-request-button"));
    await user.type(
      screen.getByLabelText(strings.impressoModalLabel),
      "Solicito exame",
    );
    await user.click(screen.getByTestId("impresso-modal-submit"));

    rerender(
      <StationScreen
        {...defaultProps}
        onRequestImpresso={onRequestImpresso}
        impressos={[]}
        impressoError="Requisição inválida."
      />,
    );

    expect(screen.getByText("Requisição inválida.")).toBeInTheDocument();
    expect(screen.getByRole("dialog")).toBeInTheDocument();
  });

  it("disables the impresso request button when the station is disabled", () => {
    render(
      <StationScreen
        {...defaultProps}
        onRequestImpresso={vi.fn()}
        impressos={[]}
        disabled
      />,
    );

    expect(screen.getByTestId("impresso-request-button")).toBeDisabled();
  });

  it("lists released impressos in the drawer and shows full content when selected", async () => {
    const user = userEvent.setup();
    render(
      <StationScreen
        {...defaultProps}
        onRequestImpresso={vi.fn()}
        impressos={[chestXray]}
      />,
    );

    await user.click(screen.getByTestId("impresso-drawer-toggle"));

    expect(screen.getByText(chestXray.title)).toBeInTheDocument();
    expect(screen.getByText(chestXray.category)).toBeInTheDocument();
    expect(screen.queryByText(chestXray.content)).not.toBeInTheDocument();

    await user.click(screen.getByTestId(`impresso-item-${chestXray.id}`));

    expect(screen.getByText(chestXray.content)).toBeInTheDocument();
  });

  it("keeps the impressos drawer available while the station is disabled", async () => {
    const user = userEvent.setup();
    render(
      <StationScreen
        {...defaultProps}
        onRequestImpresso={vi.fn()}
        impressos={[chestXray]}
        disabled
      />,
    );

    await user.click(screen.getByTestId("impresso-drawer-toggle"));

    expect(screen.getByText(chestXray.title)).toBeInTheDocument();
  });
});
