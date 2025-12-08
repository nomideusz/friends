### Build stage
FROM elixir:1.15.7-alpine AS build

ENV MIX_ENV=prod \
    LANG=C.UTF-8

RUN apk add --no-cache build-base npm git

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
FROM alpine:3.18

ENV MIX_ENV=prod \
    LANG=C.UTF-8 \
    PORT=4000 \
    PHX_SERVER=true

RUN apk add --no-cache openssl ncurses-libs libstdc++ ca-certificates

WORKDIR /app

COPY --from=build /app/_build/prod/rel/friends ./

EXPOSE 4000

COPY rel/migrate_and_start.sh /app/migrate_and_start.sh
RUN chmod +x /app/migrate_and_start.sh

CMD ["/app/migrate_and_start.sh"]

