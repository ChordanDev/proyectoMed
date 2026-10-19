import { renderHook, waitFor } from "@testing-library/react";
import { describe, expect, it, vi } from "vitest";
import { ApiError, type ActiveStation } from "../api/client";
import strings from "../i18n/pt-BR.json";
import { useActiveStation } from "./useActiveStation";

const activeStation: ActiveStation = {
  station_id: "acute-appendicitis",
  version: "2.0.0",
  display_title: "Abdome agudo inflamatório — apendicite aguda",
  language: "pt-BR",
  candidate_brief: {
    scenario: "Você é o médico de plantão.",
    tasks: ["Obter anamnese dirigida."],
  },
};

describe("useActiveStation", () => {
  it("loads the active station once on mount", async () => {
    const load = vi.fn().mockResolvedValue(activeStation);

    const { result } = renderHook(() => useActiveStation(load));

    expect(result.current).toEqual({ station: null, error: null });
    await waitFor(() => expect(result.current.station).toEqual(activeStation));
    expect(result.current.error).toBeNull();
    expect(load).toHaveBeenCalledTimes(1);
  });

  it("reports a pt-BR error when the station cannot be loaded", async () => {
    const load = vi
      .fn()
      .mockRejectedValue(new ApiError(0, "network_error", "Sem conexão."));

    const { result } = renderHook(() => useActiveStation(load));

    await waitFor(() =>
      expect(result.current.error).toBe(strings.briefUnavailable),
    );
    expect(result.current.station).toBeNull();
  });

  it("ignores a load that settles after unmount", async () => {
    let resolve: (station: ActiveStation) => void = () => undefined;
    const load = vi.fn(
      () =>
        new Promise<ActiveStation>((done) => {
          resolve = done;
        }),
    );

    const { result, unmount } = renderHook(() => useActiveStation(load));
    unmount();
    resolve(activeStation);

    await Promise.resolve();
    expect(result.current.station).toBeNull();
  });
});
