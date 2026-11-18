#!/bin/sh
set -eu
cd "$(dirname "$0")/.."

docker compose build --pull mosdns
docker compose up -d mosdns
docker compose ps mosdns
