# ---- Build Stage ----
FROM hexpm/elixir:1.19.2-erlang-28.0-debian-bookworm-20240926-slim AS build

ARG CI_JOB_TOKEN
WORKDIR /app
ENV MIX_ENV=prod

# Install git and build tools
RUN apt-get update && apt-get install -y git build-essential && rm -rf /var/lib/apt/lists/*

# install mix dependencies
COPY mix.exs mix.lock ./
RUN mix local.hex --force && mix local.rebar --force
RUN mix do deps.get, deps.compile

COPY priv priv
COPY lib lib

# Fetch the python scripts. 
# We pass dummy environment variables because the fetch task starts the application,
# which evaluates config/runtime.exs and enforces these variables in the prod environment.
# We also temporarily disable Goth to avoid it crashing on the dummy credentials.
RUN GOOGLE_SHEET_ID=dummy \
    GOOGLE_SHEET_RANGE=dummy \
    GOOGLE_DRIVE_FOLDER_ID=dummy \
    GOOGLE_APPLICATION_CREDENTIALS_JSON="{}" \
    CRAWL_ARTIFACT_DIR=dummy \
    DATABASE_URL=ecto://postgres:postgres@localhost/db \
    SECRET_KEY_BASE=dummy_secret_key_base_string_that_is_long_enough \
    mix run --no-start -e "Application.put_env(:crawl, :start_goth, false); Mix.Tasks.Crawl.Python.Fetch.run([])"

RUN mix do compile, release

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
COPY --from=build /app/priv/python/crawler-ingest/requirements.txt /app/requirements.txt
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
CMD ["./entrypoint.sh"]