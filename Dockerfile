FROM geeks5olutions/elixir_rust:1.19.2 AS build
# prepare build dir
WORKDIR /app

# set build ENV
ENV MIX_ENV=prod

# install mix dependencies
COPY mix.exs mix.lock deps ./
COPY config config
RUN mix do deps.get, deps.compile

COPY priv priv

# compile and build release
COPY lib lib

# Fetch the python scripts. 
# We pass dummy environment variables because the fetch task starts the application,
# which evaluates config/runtime.exs and enforces these variables in the prod environment.
# We also temporarily disable Goth to avoid it crashing on the dummy credentials.
RUN GOOGLE_SHEET_ID=dummy \
    GOOGLE_SHEET_RANGE=dummy \
    GOOGLE_DRIVE_FOLDER_ID=dummy \
    GOOGLE_APPLICATION_CREDENTIALS_JSON="{}" \
    DATABASE_URL=ecto://postgres:postgres@localhost/db \
    SECRET_KEY_BASE=dummy_secret_key_base_string_that_is_long_enough \
    mix run --no-start -e "Application.put_env(:crawl, :start_goth, false); Mix.Tasks.Crawl.Python.Fetch.run([])"

RUN mix do compile, release

# prepare release image
FROM alpine:3.20 AS app
RUN apk add --no-cache openssl ncurses-libs libgcc libstdc++ ffmpeg imagemagick ttf-liberation python3 py3-pip

WORKDIR /app

RUN chown nobody:nobody /app

USER nobody:nobody

# Create a python virtual environment
RUN python3 -m venv /app/.venv

# Copy python requirements and install them inside the venv
COPY --from=build --chown=nobody:nobody /app/priv/python/crawler-ingest/requirements.txt /app/requirements.txt
RUN /app/.venv/bin/pip install --no-cache-dir -r /app/requirements.txt

COPY --from=build --chown=nobody:nobody /app/_build/prod/rel ./

ENV HOME=/app
ENV PYTHON_EXECUTABLE=/app/.venv/bin/python

COPY entrypoint.sh .

# Run the Phoenix app
CMD ["./entrypoint.sh"]
