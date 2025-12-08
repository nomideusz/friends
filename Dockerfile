### Build stage
FROM hexpm/elixir:1.15.7-erlang-26.1.2-debian-bookworm-20231002 AS build

ENV MIX_ENV=prod \
    LANG=C.UTF-8

RUN apt-get update && \
    apt-get install -y build-essential npm git && \
    apt-get clean && rm -rf /var/lib/apt/lists/*

WORKDIR /app

# Install hex/rebar
RUN mix local.hex --force && mix local.rebar --force

# Prepare deps
COPY mix.exs mix.lock ./
COPY config config
RUN mix deps.get --only prod

# Build assets
COPY assets assets
RUN npm --prefix assets install
RUN mix assets.deploy

# Compile and build release
COPY lib lib
COPY priv priv
RUN mix compile
RUN mix release

### Runtime stage
FROM debian:bookworm-slim

ENV MIX_ENV=prod \
    LANG=C.UTF-8 \
    PORT=4000 \
    PHX_SERVER=true

RUN apt-get update && \
    apt-get install -y openssl libssl3 ca-certificates && \
    apt-get clean && rm -rf /var/lib/apt/lists/*

WORKDIR /app

COPY --from=build /app/_build/prod/rel/friends ./

EXPOSE 4000

CMD ["bin/friends", "start"]

