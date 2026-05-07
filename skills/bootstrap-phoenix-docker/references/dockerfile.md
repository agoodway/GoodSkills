# Dockerfile Customization

The generated Dockerfile uses multi-stage builds. Customize as needed.

## Default Structure

```dockerfile
# Stage 1: Build
ARG ELIXIR_VERSION=1.17.3
ARG OTP_VERSION=27.1.2
ARG DEBIAN_VERSION=bookworm-20240904-slim
ARG BUILDER_IMAGE="hexpm/elixir:${ELIXIR_VERSION}-erlang-${OTP_VERSION}-debian-${DEBIAN_VERSION}"
ARG RUNNER_IMAGE="debian:${DEBIAN_VERSION}"

FROM ${BUILDER_IMAGE} as builder

ENV MIX_ENV="prod"

RUN apt-get update -y && apt-get install -y build-essential git \
    && apt-get clean && rm -f /var/lib/apt/lists/*_*

WORKDIR /app

# Install hex + rebar
RUN mix local.hex --force && \
    mix local.rebar --force

# Copy dependency files
COPY mix.exs mix.lock ./
RUN mix deps.get --only $MIX_ENV
RUN mkdir config

# Copy config (except runtime.exs)
COPY config/config.exs config/${MIX_ENV}.exs config/
RUN mix deps.compile

# Copy application code
COPY priv priv
COPY lib lib
COPY assets assets

# Compile assets
RUN mix assets.deploy

# Compile application
COPY config/runtime.exs config/
RUN mix compile

# Build release
COPY rel rel
RUN mix release

# Stage 2: Runtime
FROM ${RUNNER_IMAGE}

RUN apt-get update -y && \
    apt-get install -y libstdc++6 openssl libncurses5 locales ca-certificates \
    && apt-get clean && rm -f /var/lib/apt/lists/*_*

# Set locale
RUN sed -i '/en_US.UTF-8/s/^# //g' /etc/locale.gen && locale-gen
ENV LANG en_US.UTF-8
ENV LANGUAGE en_US:en
ENV LC_ALL en_US.UTF-8

WORKDIR /app
RUN chown nobody /app
ENV MIX_ENV="prod"

# Copy release from builder
COPY --from=builder --chown=nobody:root /app/_build/${MIX_ENV}/rel/my_app ./

USER nobody

CMD ["/app/bin/server"]
```

## Common Modifications

### Add Node.js for Assets

If using npm packages in assets:

```dockerfile
# In builder stage, after apt-get install
RUN curl -fsSL https://deb.nodesource.com/setup_20.x | bash - && \
    apt-get install -y nodejs

# Before mix assets.deploy
WORKDIR /app/assets
COPY assets/package.json assets/package-lock.json ./
RUN npm ci
WORKDIR /app
```

### Add ImageMagick or FFmpeg

For image/video processing in runtime:

```dockerfile
# In runner stage
RUN apt-get update -y && \
    apt-get install -y libstdc++6 openssl libncurses5 locales ca-certificates \
    imagemagick ffmpeg \
    && apt-get clean && rm -f /var/lib/apt/lists/*_*
```

### Add curl for Health Checks

```dockerfile
# In runner stage
RUN apt-get update -y && \
    apt-get install -y libstdc++6 openssl libncurses5 locales ca-certificates curl \
    && apt-get clean && rm -f /var/lib/apt/lists/*_*

HEALTHCHECK --interval=30s --timeout=3s --start-period=5s --retries=3 \
  CMD curl -f http://localhost:4000/health || exit 1
```

### Pin Specific Versions

For reproducible builds:

```dockerfile
ARG ELIXIR_VERSION=1.17.3
ARG OTP_VERSION=27.1.2
ARG DEBIAN_VERSION=bookworm-20240904-slim
```

### Multi-Platform Builds

Build for multiple architectures:

```bash
docker buildx build --platform linux/amd64,linux/arm64 -t my_app:latest .
```

### Reduce Image Size

Use Alpine (requires musl-compatible dependencies):

```dockerfile
ARG BUILDER_IMAGE="hexpm/elixir:${ELIXIR_VERSION}-erlang-${OTP_VERSION}-alpine-3.19.1"
ARG RUNNER_IMAGE="alpine:3.19.1"

# In runner stage
RUN apk add --no-cache libstdc++ openssl ncurses-libs
```

## Build Arguments

Pass at build time:

```bash
docker build \
  --build-arg ELIXIR_VERSION=1.17.3 \
  --build-arg OTP_VERSION=27.1.2 \
  -t my_app:latest .
```

## Layer Caching

The Dockerfile is structured for optimal caching:
1. Dependencies (mix.exs, mix.lock) - rarely change
2. Config files - occasionally change
3. Application code - frequently changes
4. Assets - changes with frontend updates
