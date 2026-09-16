import React, { useState } from "react";
import { Pressable, ScrollView, StyleSheet, Text, View } from "react-native";
import strings from "../i18n/pt-BR.json";

export interface NoticeScreenProps {
  onStart: (consent: boolean) => void | Promise<void>;
  voiceSupport?: boolean;
}

export function NoticeScreen({
  onStart,
  voiceSupport = true,
}: NoticeScreenProps): React.JSX.Element {
  const [consentChecked, setConsentChecked] = useState(false);

  const isButtonDisabled = voiceSupport && !consentChecked;

  const handlePress = () => {
    if (isButtonDisabled) return;
    void onStart(voiceSupport ? true : false);
  };

  const handleCheckboxPress = () => {
    setConsentChecked((prev) => !prev);
  };

  return (
    <ScrollView
      contentContainerStyle={styles.container}
      testID="notice-screen-scroll"
    >
      {/* Educational notice */}
      <Text style={styles.title}>{strings.noticeTitle}</Text>
      <Text style={styles.body}>{strings.noticeBody}</Text>

      {/* Audio disclosure + consent (voice only) */}
      {voiceSupport && (
        <View style={styles.disclosureBlock}>
          <Text style={styles.disclosure}>{strings.audioDisclosure}</Text>
          <Pressable
            accessibilityRole="checkbox"
            accessibilityState={{ checked: consentChecked }}
            onPress={handleCheckboxPress}
            style={styles.checkboxRow}
            testID="consent-checkbox"
          >
            <View
              style={[
                styles.checkboxBox,
                consentChecked && styles.checkboxBoxChecked,
              ]}
            />
            <Text style={styles.checkboxLabel}>
              {strings.consentCheckboxLabel}
            </Text>
          </Pressable>
        </View>
      )}

      {/* Primary action button */}
      <Pressable
        accessibilityRole="button"
        accessibilityLabel={strings.noticeButton}
        accessibilityState={{ disabled: isButtonDisabled }}
        disabled={isButtonDisabled}
        onPress={handlePress}
        style={[styles.button, isButtonDisabled && styles.buttonDisabled]}
        testID="notice-button"
      >
        <Text style={styles.buttonText}>{strings.noticeButton}</Text>
      </Pressable>
    </ScrollView>
  );
}

const styles = StyleSheet.create({
  container: {
    padding: 24,
    flexGrow: 1,
  },
  title: {
    fontSize: 20,
    fontWeight: "700",
    marginBottom: 12,
    color: "#111827",
  },
  body: {
    fontSize: 15,
    lineHeight: 22,
    color: "#374151",
    marginBottom: 20,
  },
  disclosureBlock: {
    backgroundColor: "#FEF9C3",
    borderRadius: 8,
    padding: 16,
    marginBottom: 20,
  },
  disclosure: {
    fontSize: 13,
    lineHeight: 20,
    color: "#374151",
    marginBottom: 12,
  },
  checkboxRow: {
    flexDirection: "row",
    alignItems: "center",
    gap: 10,
  },
  checkboxBox: {
    width: 20,
    height: 20,
    borderRadius: 4,
    borderWidth: 2,
    borderColor: "#6B7280",
    backgroundColor: "#FFFFFF",
  },
  checkboxBoxChecked: {
    backgroundColor: "#2563EB",
    borderColor: "#2563EB",
  },
  checkboxLabel: {
    fontSize: 14,
    color: "#111827",
    flex: 1,
  },
  button: {
    backgroundColor: "#2563EB",
    borderRadius: 8,
    paddingVertical: 14,
    alignItems: "center",
  },
  buttonDisabled: {
    backgroundColor: "#9CA3AF",
  },
  buttonText: {
    color: "#FFFFFF",
    fontSize: 16,
    fontWeight: "600",
  },
});
