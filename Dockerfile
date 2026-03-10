# ---- Build Stage ----
FROM elixir:1.19.2-otp-28-slim AS build

WORKDIR /app
ENV MIX_ENV=prod

# Install git and build tools
RUN apt-get update && apt-get install -y git build-essential && rm -rf /var/lib/apt/lists/*

# install mix dependencies
COPY mix.exs mix.lock ./
RUN mix local.hex --force && mix local.rebar --force
RUN mix do deps.get, deps.compile

COPY config config
COPY priv priv
COPY lib lib

# Fetch the python scripts.
# MIX_ENV=prod evaluates config/runtime.exs, which enforces required prod env vars.
RUN GOOGLE_SHEET_ID=dummy \
    GOOGLE_SHEET_RANGE=dummy \
    GOOGLE_DRIVE_FOLDER_ID=dummy \
    GOOGLE_APPLICATION_CREDENTIALS_JSON="{}" \
    CRAWL_ARTIFACT_DIR=dummy \
    DATABASE_URL=ecto://postgres:postgres@localhost/db \
    SECRET_KEY_BASE=dummy_secret_key_base_string_that_is_long_enough \
    mix crawl.python.fetch

RUN mix do compile, release

# Keep a stable path to the release-bundled Python requirements
RUN cp /app/_build/prod/rel/crawl/lib/crawl-*/priv/python/crawler-ingest/requirements.txt /app/release-requirements.txt

# ---- Run Stage ----
FROM debian:bookworm-slim AS app

# Install runtime dependencies
RUN apt-get update && apt-get install -y \
    openssl \
    libncurses6 \
    libstdc++6 \
    ffmpeg \
    imagemagick \
    fonts-liberation \
    python3 \
    python3-pip \
    python3-venv \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /app

# Create python venv & install deps
RUN python3 -m venv /app/.venv
COPY --from=build /app/release-requirements.txt /app/requirements.txt
RUN /app/.venv/bin/pip install --no-cache-dir -r /app/requirements.txt

# Install Playwright and its system dependencies
ENV PLAYWRIGHT_BROWSERS_PATH=/app/pw-browsers
RUN /app/.venv/bin/playwright install chromium
RUN /app/.venv/bin/playwright install-deps chromium

# Secure the app directory
RUN chown -R nobody:nogroup /app
USER nobody:nogroup

COPY --from=build --chown=nobody:nogroup /app/_build/prod/rel ./

ENV HOME=/app
ENV PYTHON_EXECUTABLE=/app/.venv/bin/python

COPY --chown=nobody:nogroup entrypoint.sh .

# Run the Phoenix app
CMD ["sh", "./entrypoint.sh"]
