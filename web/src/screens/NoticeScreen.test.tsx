import { act, render, fireEvent } from "@testing-library/react";
import { NoticeScreen } from "./NoticeScreen";
import strings from "../i18n/pt-BR.json";

describe("NoticeScreen", () => {
  describe("shared: renders educational notice and primary button", () => {
    it("shows the notice title and body text", async () => {
      const onStart = vi.fn();
      const { getByText } = await render(
        <NoticeScreen onStart={onStart} voiceSupport={false} />,
      );
      expect(getByText(strings.noticeTitle)).toBeTruthy();
      expect(getByText(strings.noticeBody)).toBeTruthy();
    });

    it("shows the 'Entendi' button", async () => {
      const onStart = vi.fn();
      const { getByText } = await render(
        <NoticeScreen onStart={onStart} voiceSupport={false} />,
      );
      expect(getByText(strings.noticeButton)).toBeTruthy();
    });
  });

  describe("voiceSupport: true (default)", () => {
    it("renders audio disclosure text", async () => {
      const onStart = vi.fn();
      const { getByText } = await render(<NoticeScreen onStart={onStart} />);
      expect(getByText(strings.audioDisclosure)).toBeTruthy();
    });

    it("renders consent checkbox label", async () => {
      const onStart = vi.fn();
      const { getByText } = await render(<NoticeScreen onStart={onStart} />);
      expect(getByText(strings.consentCheckboxLabel)).toBeTruthy();
    });

    it("'Entendi' button is disabled when checkbox is unchecked", async () => {
      const onStart = vi.fn();
      const { getByTestId } = await render(<NoticeScreen onStart={onStart} />);
      const button = getByTestId("notice-button");
      expect(button).toBeDisabled();
    });

    it("'Entendi' button is enabled after checking the consent checkbox", async () => {
      const onStart = vi.fn();
      const { getByTestId } = await render(<NoticeScreen onStart={onStart} />);
      const checkbox = getByTestId("consent-checkbox").querySelector("input")!;
      await act(async () => {
        fireEvent.click(checkbox);
      });
      const button = getByTestId("notice-button");
      expect(button).not.toBeDisabled();
    });

    it("disables 'Entendi' again after unchecking the checkbox", async () => {
      const onStart = vi.fn();
      const { getByTestId } = await render(<NoticeScreen onStart={onStart} />);
      const checkbox = getByTestId("consent-checkbox").querySelector("input")!;
      await act(async () => {
        fireEvent.click(checkbox); // check
      });
      await act(async () => {
        fireEvent.click(checkbox); // uncheck
      });
      const button = getByTestId("notice-button");
      expect(button).toBeDisabled();
    });

    it("calls onStart(true) when consent is given and button is pressed", async () => {
      const onStart = vi.fn();
      const { getByTestId } = await render(<NoticeScreen onStart={onStart} />);
      const checkbox = getByTestId("consent-checkbox").querySelector("input")!;
      await act(async () => {
        fireEvent.click(checkbox);
      });
      const button = getByTestId("notice-button");
      await act(async () => {
        fireEvent.click(button);
      });
      expect(onStart).toHaveBeenCalledTimes(1);
      expect(onStart).toHaveBeenCalledWith(true);
    });

    it("checkbox aria-checked toggles on click", async () => {
      const onStart = vi.fn();
      const { getByTestId } = await render(<NoticeScreen onStart={onStart} />);
      const checkbox = getByTestId("consent-checkbox").querySelector("input")!;
      expect(checkbox).not.toBeChecked();
      await act(async () => {
        fireEvent.click(checkbox);
      });
      expect(checkbox).toBeChecked();
    });
  });

  describe("voiceSupport: false", () => {
    it("does NOT render audio disclosure", async () => {
      const onStart = vi.fn();
      const { queryByText } = await render(
        <NoticeScreen onStart={onStart} voiceSupport={false} />,
      );
      expect(queryByText(strings.audioDisclosure)).toBeNull();
    });

    it("does NOT render consent checkbox", async () => {
      const onStart = vi.fn();
      const { queryByText } = await render(
        <NoticeScreen onStart={onStart} voiceSupport={false} />,
      );
      expect(queryByText(strings.consentCheckboxLabel)).toBeNull();
    });

    it("'Entendi' button is enabled by default", async () => {
      const onStart = vi.fn();
      const { getByTestId } = await render(
        <NoticeScreen onStart={onStart} voiceSupport={false} />,
      );
      const button = getByTestId("notice-button");
      expect(button).not.toBeDisabled();
    });

    it("calls onStart(false) when button is pressed", async () => {
      const onStart = vi.fn();
      const { getByTestId } = await render(
        <NoticeScreen onStart={onStart} voiceSupport={false} />,
      );
      const button = getByTestId("notice-button");
      await act(async () => {
        fireEvent.click(button);
      });
      expect(onStart).toHaveBeenCalledTimes(1);
      expect(onStart).toHaveBeenCalledWith(false);
    });
  });
});
