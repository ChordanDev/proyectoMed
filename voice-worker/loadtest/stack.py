"""The local stack the load test runs against (#401), with no paid provider.

`livekit-server --dev` on its own ports, the mock OpenAI of the voice stack (#191),
Phoenix in dev on its own port and database with the approving Jev adapter, and one
voice worker with its fake speech providers. Every process starts from `clean_env`,
an allow-list of toolchain variables, so no provider key or URL from the caller's
shell reaches them, and no `.env` file is ever read. Stopping the stack stops every
process group it started.
"""

import dataclasses
import os
import secrets
import signal
import socket
import subprocess
import time
import urllib.request
from pathlib import Path
from urllib.parse import urlparse

LOOPBACK = {"127.0.0.1", "localhost", "::1"}
ROOT = Path(__file__).resolve().parents[2]
KEEP_VARIABLES = {"PATH", "HOME", "USER", "LOGNAME", "SHELL", "TMPDIR", "LANG", "TERM"}
KEEP_PREFIXES = ("LC_", "MIX_", "HEX_", "ERL_", "ASDF_", "MISE_", "UV_")
LIVEKIT_KEY = "devkey"
LIVEKIT_SECRET = "secret"  # the `--dev` placeholder keys of livekit-server
PATIENT_REPLY = "Meu nome é Carlos."


@dataclasses.dataclass(frozen=True)
class Ports:
    """Away from the developer's Phoenix (4000/4001), Vite (5173) and LiveKit (7880-7882)."""

    livekit: int = 7990
    livekit_tcp: int = 7991
    livekit_udp: int = 7992
    phoenix: int = 4159
    mock_llm: int = 18866


def clean_env(environ) -> dict:
    return {
        key: value
        for key, value in environ.items()
        if key in KEEP_VARIABLES or key.startswith(KEEP_PREFIXES)
    }


def require_loopback(url: str) -> str:
    crafted = any(c in "\\@" or c.isspace() or not c.isprintable() for c in url)
    if crafted or urlparse(url).hostname not in LOOPBACK:
        raise ValueError(f"load test refuses a non-loopback URL: {url!r}")
    return url


def livekit_url(ports: Ports) -> str:
    return f"ws://127.0.0.1:{ports.livekit}"


def phoenix_url(ports: Ports) -> str:
    return f"http://127.0.0.1:{ports.phoenix}"


def livekit_config_body(ports: Ports) -> str:
    return (
        f"port: {ports.livekit}\n"
        "rtc:\n"
        f"  tcp_port: {ports.livekit_tcp}\n"
        f"  udp_port: {ports.livekit_udp}\n"
        "room:\n"
        "  empty_timeout: 10\n"
        "  departure_timeout: 5\n"
    )


def _livekit_env(ports: Ports) -> dict:
    return {
        "LIVEKIT_URL": livekit_url(ports),
        "LIVEKIT_API_KEY": LIVEKIT_KEY,
        "LIVEKIT_API_SECRET": LIVEKIT_SECRET,
    }


def phoenix_env(environ, ports: Ports, worker_secret: str, database: str) -> dict:
    return {
        **clean_env(environ),
        **_livekit_env(ports),
        "MIX_ENV": "dev",
        "PORT": str(ports.phoenix),
        "PHX_SERVER": "true",
        "DATABASE_URL": f"ecto://localhost/{database}",
        "VOICE_MODE": "realtime",
        "VOICE_WORKER_SECRET": worker_secret,
        "OPENAI_API_KEY": "load-test-stub-key",
        "OPENAI_BASE_URL": f"http://127.0.0.1:{ports.mock_llm}",
        "JEV_E2E_APPROVING_ADAPTER": "true",
    }


def worker_env(environ, ports: Ports, worker_secret: str) -> dict:
    return {
        **clean_env(environ),
        **_livekit_env(ports),
        "PHOENIX_URL": phoenix_url(ports),
        "VOICE_WORKER_SECRET": worker_secret,
        "VOICE_WORKER_FAKE_PROVIDERS": "true",
    }


def port_open(port: int) -> bool:
    with socket.socket() as sock:
        sock.settimeout(0.5)
        return sock.connect_ex(("127.0.0.1", port)) == 0


class Stack:
    """Starts the four processes, each in its own process group, and stops them all."""

    def __init__(self, ports: Ports, database: str, logs: Path):
        self.ports = ports
        self.database = database
        self.logs = logs
        self.secret = "load-test-" + secrets.token_hex(8)
        self.procs: dict[str, subprocess.Popen] = {}

    def _spawn(self, name: str, args, cwd: Path, env: dict) -> subprocess.Popen:
        log = open(self.logs / f"{name}.log", "wb")  # noqa: SIM115 - lives with the process
        proc = subprocess.Popen(
            args,
            cwd=cwd,
            env=env,
            stdout=log,
            stderr=subprocess.STDOUT,
            stdin=subprocess.DEVNULL,
            start_new_session=True,
        )
        self.procs[name] = proc
        return proc

    def _wait(self, name: str, ready, seconds: float) -> None:
        deadline = time.monotonic() + seconds
        while time.monotonic() < deadline:
            if ready():
                print(f"load test: {name} ready", flush=True)
                return
            if self.procs[name].poll() is not None:
                raise RuntimeError(f"{name} exited (logs: {self.logs})")
            time.sleep(1)
        raise RuntimeError(f"{name} not ready in {seconds:.0f}s (logs: {self.logs})")

    def start(self) -> None:
        p = self.ports
        busy = [port for port in dataclasses.astuple(p) if port_open(port)]
        if busy:
            raise RuntimeError(f"ports already in use: {busy}")
        base = dict(os.environ)
        backend = ROOT / "backend"
        self._spawn(
            "livekit",
            [
                "livekit-server",
                "--dev",
                "--bind",
                "127.0.0.1",
                "--config-body",
                livekit_config_body(p),
            ],
            ROOT,
            clean_env(base),
        )
        self._spawn(
            "mock-llm",
            [
                "python3",
                str(ROOT / "scripts/voice-stack/mock_openai.py"),
                str(p.mock_llm),
            ],
            ROOT,
            {**clean_env(base), "MOCK_LLM_REPLY": PATIENT_REPLY},
        )
        env = phoenix_env(base, p, self.secret, self.database)
        with open(self.logs / "ecto.log", "wb") as log:
            setup = subprocess.run(
                ["mix", "do", "ecto.create", "--quiet", "+", "ecto.migrate", "--quiet"],
                cwd=backend,
                env=env,
                stdout=log,
                stderr=subprocess.STDOUT,
                check=False,
            )
        if setup.returncode != 0:
            raise RuntimeError(f"database setup failed (logs: {self.logs})")
        self._spawn("phoenix", ["mix", "phx.server"], backend, env)
        self._wait("livekit", lambda: _get(f"http://127.0.0.1:{p.livekit}"), 30)
        self._wait("mock-llm", lambda: _get(f"http://127.0.0.1:{p.mock_llm}"), 10)
        self._wait(
            "phoenix",
            lambda: (
                '"voice_mode":"realtime"'
                in (_get(phoenix_url(p) + "/api/stations/active") or "")
            ),
            300,
        )
        # `dev`: no CPU-load cap, so the worker takes every job and degradation shows;
        # `worker_entry` adds the production number of warm job processes.
        self._spawn(
            "worker",
            [
                "uv",
                "run",
                "python",
                "-m",
                "loadtest.worker_entry",
                "dev",
                "--no-reload",
                "--log-level",
                "INFO",
            ],
            ROOT / "voice-worker",
            worker_env(base, p, self.secret),
        )
        self._wait(
            "worker",
            lambda: b"registered worker" in (self.logs / "worker.log").read_bytes(),
            120,
        )

    def stop(self) -> None:
        for proc in reversed(list(self.procs.values())):
            if proc.poll() is None:
                try:
                    os.killpg(proc.pid, signal.SIGTERM)
                except ProcessLookupError:
                    pass
        for proc in self.procs.values():
            try:
                proc.wait(timeout=20)
            except subprocess.TimeoutExpired:
                try:
                    os.killpg(proc.pid, signal.SIGKILL)
                except ProcessLookupError:
                    pass
                proc.wait()


def _get(url: str) -> str | None:
    try:
        with urllib.request.urlopen(require_loopback(url), timeout=2) as response:
            return response.read().decode()
    except OSError:
        return None
