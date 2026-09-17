import React from "react";
import { NoticeScreen } from "./screens/NoticeScreen";
import "./index.css";

export default function App(): React.JSX.Element {
  return (
    <main className="app-root">
      <NoticeScreen
        onStart={(consent: boolean) => console.log("start", consent)}
      />
    </main>
  );
}
