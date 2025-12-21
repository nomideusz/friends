### Build stage (Debian + Node 20)
# Use Debian instead of Alpine to avoid potential DNS / libc issues in production.

ARG ELIXIR_VERSION=1.16.0
ARG OTP_VERSION=26.2.1
ARG DEBIAN_VERSION=bullseye-20231009-slim

ARG BUILDER_IMAGE="hexpm/elixir:${ELIXIR_VERSION}-erlang-${OTP_VERSION}-debian-${DEBIAN_VERSION}"
ARG RUNNER_IMAGE="debian:${DEBIAN_VERSION}"

FROM ${BUILDER_IMAGE} as build

# Install build dependencies and Node.js 20.x (>=20.6.0)
RUN apt-get update -y && apt-get install -y build-essential git curl \
    && curl -fsSL https://deb.nodesource.com/setup_20.x | bash - \
    && apt-get update -y \
    && apt-get install -y nodejs \
    && apt-get clean && rm -f /var/lib/apt/lists/*_*

WORKDIR /app

# Install hex/rebar
RUN mix local.hex --force && mix local.rebar --force

# Build env
ENV MIX_ENV=prod

# Deps
COPY mix.exs mix.lock ./
RUN mix deps.get --only $MIX_ENV
RUN mkdir config
COPY config/config.exs config/${MIX_ENV}.exs config/
RUN mix deps.compile

# Copy app
COPY priv priv
COPY assets assets
COPY lib lib

# Build assets
# NOTE: We skip manual `node build.js` here because `mix assets.deploy` runs it.
WORKDIR /app/assets
RUN npm ci --prefer-offline --no-audit

# Tailwind (if configured via mix)
WORKDIR /app
RUN mix tailwind.install --if-missing
RUN mix assets.deploy

# Compile
RUN mix compile

# Runtime config
COPY config/runtime.exs config/

# Digest & release
RUN mix phx.digest
RUN mix release

### Runtime stage
FROM ${RUNNER_IMAGE}

# Runtime deps
RUN apt-get update -y && \
    apt-get install -y libstdc++6 openssl libncurses5 locales ca-certificates curl && \
    apt-get clean && rm -f /var/lib/apt/lists/*_*

# Locale
RUN sed -i '/en_US.UTF-8/s/^# //g' /etc/locale.gen && locale-gen
ENV LANG=en_US.UTF-8 \
    LANGUAGE=en_US:en \
    LC_ALL=en_US.UTF-8 \
    MIX_ENV=prod \
    PORT=4000 \
    PHX_SERVER=true

WORKDIR /app

# Copy release
COPY --from=build /app/_build/prod/rel/friends ./

# Copy migrate/start wrapper
COPY rel/migrate_and_start.sh /app/migrate_and_start.sh

# Fix line endings (CRLF -> LF) to prevent "exec format error" or "no such file" on Linux
RUN sed -i 's/\r$//' /app/migrate_and_start.sh
RUN chmod +x /app/migrate_and_start.sh

EXPOSE 4000

# Run migrations then start
CMD ["/app/migrate_and_start.sh"]

