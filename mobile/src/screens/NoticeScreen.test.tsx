import React from "react";
import { act, render, fireEvent } from "@testing-library/react-native";
import { NoticeScreen } from "./NoticeScreen";
import strings from "../i18n/pt-BR.json";

describe("NoticeScreen", () => {
  describe("shared: renders educational notice and primary button", () => {
    it("shows the notice title and body text", async () => {
      const onStart = jest.fn();
      const { getByText } = await render(
        <NoticeScreen onStart={onStart} voiceSupport={false} />,
      );
      expect(getByText(strings.noticeTitle)).toBeTruthy();
      expect(getByText(strings.noticeBody)).toBeTruthy();
    });

    it("shows the 'Entendi' button", async () => {
      const onStart = jest.fn();
      const { getByText } = await render(
        <NoticeScreen onStart={onStart} voiceSupport={false} />,
      );
      expect(getByText(strings.noticeButton)).toBeTruthy();
    });
  });

  describe("voiceSupport: true (default)", () => {
    it("renders audio disclosure text", async () => {
      const onStart = jest.fn();
      const { getByText } = await render(<NoticeScreen onStart={onStart} />);
      expect(getByText(strings.audioDisclosure)).toBeTruthy();
    });

    it("renders consent checkbox label", async () => {
      const onStart = jest.fn();
      const { getByText } = await render(<NoticeScreen onStart={onStart} />);
      expect(getByText(strings.consentCheckboxLabel)).toBeTruthy();
    });

    it("'Entendi' button is disabled when checkbox is unchecked", async () => {
      const onStart = jest.fn();
      const { getByText } = await render(<NoticeScreen onStart={onStart} />);
      const button = getByText(strings.noticeButton).parent;
      expect(button?.props.accessibilityState?.disabled).toBe(true);
    });

    it("'Entendi' button is enabled after checking the consent checkbox", async () => {
      const onStart = jest.fn();
      const { getByText } = await render(<NoticeScreen onStart={onStart} />);
      const checkbox = getByText(strings.consentCheckboxLabel).parent;
      await act(async () => {
        fireEvent.press(checkbox!);
      });
      const button = getByText(strings.noticeButton).parent;
      expect(button?.props.accessibilityState?.disabled).toBe(false);
    });

    it("disables 'Entendi' again after unchecking the checkbox", async () => {
      const onStart = jest.fn();
      const { getByText } = await render(<NoticeScreen onStart={onStart} />);
      const checkbox = getByText(strings.consentCheckboxLabel).parent;
      await act(async () => {
        fireEvent.press(checkbox!); // check
      });
      await act(async () => {
        fireEvent.press(checkbox!); // uncheck
      });
      const button = getByText(strings.noticeButton).parent;
      expect(button?.props.accessibilityState?.disabled).toBe(true);
    });

    it("calls onStart(true) when consent is given and button is pressed", async () => {
      const onStart = jest.fn();
      const { getByText } = await render(<NoticeScreen onStart={onStart} />);
      const checkbox = getByText(strings.consentCheckboxLabel).parent;
      await act(async () => {
        fireEvent.press(checkbox!);
      });
      const button = getByText(strings.noticeButton).parent;
      await act(async () => {
        fireEvent.press(button!);
      });
      expect(onStart).toHaveBeenCalledTimes(1);
      expect(onStart).toHaveBeenCalledWith(true);
    });

    it("checkbox accessibilityState.checked toggles on press", async () => {
      const onStart = jest.fn();
      const { getByText } = await render(<NoticeScreen onStart={onStart} />);
      const checkbox = getByText(strings.consentCheckboxLabel).parent;
      expect(checkbox?.props.accessibilityState?.checked).toBe(false);
      await act(async () => {
        fireEvent.press(checkbox!);
      });
      expect(checkbox?.props.accessibilityState?.checked).toBe(true);
    });
  });

  describe("voiceSupport: false", () => {
    it("does NOT render audio disclosure", async () => {
      const onStart = jest.fn();
      const { queryByText } = await render(
        <NoticeScreen onStart={onStart} voiceSupport={false} />,
      );
      expect(queryByText(strings.audioDisclosure)).toBeNull();
    });

    it("does NOT render consent checkbox", async () => {
      const onStart = jest.fn();
      const { queryByText } = await render(
        <NoticeScreen onStart={onStart} voiceSupport={false} />,
      );
      expect(queryByText(strings.consentCheckboxLabel)).toBeNull();
    });

    it("'Entendi' button is enabled by default", async () => {
      const onStart = jest.fn();
      const { getByText } = await render(
        <NoticeScreen onStart={onStart} voiceSupport={false} />,
      );
      const button = getByText(strings.noticeButton).parent;
      const disabled = button?.props.accessibilityState?.disabled;
      expect(disabled === false || disabled === undefined).toBe(true);
    });

    it("calls onStart(false) when button is pressed", async () => {
      const onStart = jest.fn();
      const { getByText } = await render(
        <NoticeScreen onStart={onStart} voiceSupport={false} />,
      );
      const button = getByText(strings.noticeButton).parent;
      await act(async () => {
        fireEvent.press(button!);
      });
      expect(onStart).toHaveBeenCalledTimes(1);
      expect(onStart).toHaveBeenCalledWith(false);
    });
  });
});
