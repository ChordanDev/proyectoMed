import React from "react";
import { StationSession } from "./features/station";
import "./index.css";

export default function App(): React.JSX.Element {
  return (
    <main className="app-root">
      <StationSession />
    </main>
  );
}
