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
# uncomment COPY if rel/ exists
# COPY rel rel
RUN mix do compile, release

# prepare release image
FROM alpine:3.20 AS app
RUN apk add --no-cache openssl ncurses-libs libgcc libstdc++ ffmpeg imagemagick ttf-liberation

WORKDIR /app

RUN chown nobody:nobody /app

USER nobody:nobody

COPY --from=build --chown=nobody:nobody /app/_build/prod/rel ./

ENV HOME=/app

COPY entrypoint.sh .

# Run the Phoenix app
CMD ["./entrypoint.sh"]
