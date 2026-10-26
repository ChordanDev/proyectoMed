# Production image of the Phoenix backend (#344), built by `fly deploy` from
# `backend/`. Versions match `.tool-versions`; images come from
# https://hub.docker.com/r/hexpm/elixir/tags and
# https://hub.docker.com/_/debian?tab=tags.
ARG ELIXIR_VERSION=1.20.2
ARG OTP_VERSION=29.0.5
ARG DEBIAN_VERSION=trixie-20260713-slim

ARG BUILDER_IMAGE="hexpm/elixir:${ELIXIR_VERSION}-erlang-${OTP_VERSION}-debian-${DEBIAN_VERSION}"
ARG RUNNER_IMAGE="debian:${DEBIAN_VERSION}"

FROM ${BUILDER_IMAGE} AS builder

RUN apt-get update \
  && apt-get install -y --no-install-recommends build-essential git ca-certificates \
  && rm -rf /var/lib/apt/lists/*

WORKDIR /app

RUN mix local.hex --force && mix local.rebar --force

ENV MIX_ENV="prod"

# Dependencies first, so a source-only change reuses this layer.
COPY mix.exs mix.lock ./
RUN mix deps.get --only $MIX_ENV
RUN mkdir config

# Compile-time configuration; runtime.exs is copied later and read at boot.
COPY config/config.exs config/${MIX_ENV}.exs config/
RUN mix deps.compile

RUN mix assets.setup

COPY priv priv
COPY lib lib
COPY assets assets

RUN mix compile
RUN mix assets.deploy

COPY config/runtime.exs config/
COPY rel rel
RUN mix release

FROM ${RUNNER_IMAGE} AS runner

RUN apt-get update \
  && apt-get install -y --no-install-recommends libstdc++6 openssl libncurses6 locales ca-certificates \
  && rm -rf /var/lib/apt/lists/*

RUN sed -i '/en_US.UTF-8/s/^# //g' /etc/locale.gen && locale-gen

ENV LANG=en_US.UTF-8 \
    LANGUAGE=en_US:en \
    LC_ALL=en_US.UTF-8 \
    MIX_ENV="prod" \
    PORT="8080"

WORKDIR /app
RUN chown nobody /app

COPY --from=builder --chown=nobody:root /app/_build/prod/rel/backend ./

USER nobody

EXPOSE 8080

CMD ["/app/bin/server"]
