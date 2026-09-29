# syntax=docker/dockerfile:1.7

ARG ELIXIR_VERSION=1.19.5
ARG OTP_VERSION=28.3.1
ARG UBUNTU_VERSION=noble-20260210.1

FROM hexpm/elixir:${ELIXIR_VERSION}-erlang-${OTP_VERSION}-ubuntu-${UBUNTU_VERSION} AS build

ARG HEX_ORG_NAME=defdo
ENV MIX_ENV=prod

RUN apt-get update \
    && apt-get install --no-install-recommends -y build-essential ca-certificates cargo curl git nodejs npm \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /app

RUN mix do local.hex --force + local.rebar --force

COPY mix.exs mix.lock .formatter.exs VERSION ./
COPY config/ config/

# Authenticate and resolve in the same layer so the generated Hex config is
# removed before BuildKit stores the layer. The token itself is a BuildKit
# secret and never becomes a build arg or image environment variable.
RUN --mount=type=secret,id=hex_org_token,required=true \
    token="$(tr -d '[:space:]' < /run/secrets/hex_org_token)" \
    && mix hex.organization auth "$HEX_ORG_NAME" --key "$token" \
    && mix deps.get --check-locked \
    && rm -f /root/.hex/hex.config

COPY assets/ assets/
COPY lib/ lib/
COPY priv/ priv/

RUN mix assets.setup
RUN mix assets.deploy
RUN mix release

FROM ubuntu:${UBUNTU_VERSION} AS runtime

ARG VCS_REF=unknown
LABEL org.opencontainers.image.revision=$VCS_REF

RUN apt-get update \
    && apt-get install --no-install-recommends -y ca-certificates ffmpeg libncurses6 libstdc++6 openssl \
    && groupadd --gid 568 koe \
    && useradd --uid 568 --gid 568 --create-home --home-dir /home/koe --shell /usr/sbin/nologin koe \
    && mkdir -p /media \
    && chown 568:568 /media \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /app
COPY --from=build --chown=568:568 /app/_build/prod/rel/koe_frame ./

ENV PHX_SERVER=true
ENV PORT=4000

EXPOSE 4000
USER 568:568
ENTRYPOINT ["/app/bin/koe_frame"]
CMD ["start"]
