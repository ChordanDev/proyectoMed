import { useEffect, useState } from "react";
import { getActiveStation, type ActiveStation } from "../api/client";
import strings from "../i18n/pt-BR.json";

export interface ActiveStationState {
  /** The active station metadata and brief, once loaded. */
  station: ActiveStation | null;
  /** pt-BR notice when the active station could not be loaded. */
  error: string | null;
}

/**
 * Loads the active station (title and candidate brief) once on mount. A
 * failure leaves `station` null and sets a learner-facing notice; the station
 * can still be started without the brief.
 */
export const useActiveStation = (
  load: () => Promise<ActiveStation> = getActiveStation,
): ActiveStationState => {
  const [state, setState] = useState<ActiveStationState>({
    station: null,
    error: null,
  });

  useEffect(() => {
    let mounted = true;
    load().then(
      (station) => {
        if (mounted) setState({ station, error: null });
      },
      () => {
        if (mounted) setState({ station: null, error: strings.briefUnavailable });
      },
    );
    return () => {
      mounted = false;
    };
    // Load once per mount; a new loader identity must not refetch.
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, []);

  return state;
};
