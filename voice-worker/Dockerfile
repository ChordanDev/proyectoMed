# Production image of the LiveKit voice worker (#344): a self-hosted agent
# server in Fly `gru` connected to LiveKit Cloud (decision 2026-10-22 on #344).
# It has no public HTTP service; LiveKit dispatches jobs over its outbound
# connection. Images: https://hub.docker.com/_/python and
# https://github.com/astral-sh/uv/pkgs/container/uv.
FROM ghcr.io/astral-sh/uv:0.12.23 AS uv

FROM python:3.13.12-slim-trixie

COPY --from=uv /uv /usr/local/bin/uv

ENV PYTHONUNBUFFERED=1 \
    UV_COMPILE_BYTECODE=1 \
    UV_LINK_MODE=copy \
    UV_PYTHON_DOWNLOADS=never

WORKDIR /app

# Dependencies first, so a source-only change reuses this layer.
COPY pyproject.toml uv.lock ./
RUN uv sync --frozen --no-dev --no-install-project

COPY *.py ./
RUN rm -f test_*.py

RUN useradd --system --uid 10001 worker
USER worker

# The agent server's health check (`/` on 8081 in `start` mode).
EXPOSE 8081

CMD ["/app/.venv/bin/python", "worker.py", "start"]
