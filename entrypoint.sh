#!/bin/sh
# Docker entrypoint script.
# We run migrations if needed
./crawl/bin/crawl eval "Crawl.Release.migrate"

./crawl/bin/crawl start