#!/bin/sh
set -eu
cd "$(dirname "$0")/.."
docker compose exec -T mosdns /usr/local/bin/update-rules.sh latest
docker compose restart mosdns
