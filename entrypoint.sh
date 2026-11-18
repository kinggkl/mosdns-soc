#!/bin/sh
set -eu

export ECS_PRESET="${ECS_PRESET:-}"
export DNS_LISTEN="${DNS_LISTEN:-:53}"
export LOG_LEVEL="${LOG_LEVEL:-debug}"
export CACHE_WAN_SIZE="${CACHE_WAN_SIZE:-131072}"
export CACHE_LAN_SIZE="${CACHE_LAN_SIZE:-8192}"

mkdir -p /etc/mosdns/cache /run/mosdns
/usr/local/bin/update-rules.sh --seed

envsubst '${ECS_PRESET}' </etc/mosdns/dns.yaml.tpl >/etc/mosdns/dns.yaml
envsubst '${LOG_LEVEL} ${DNS_LISTEN}' </etc/mosdns/config.yaml >/run/mosdns/config.yaml
envsubst '${CACHE_WAN_SIZE} ${CACHE_LAN_SIZE}' </etc/mosdns/dat_exec.yaml >/run/mosdns/dat_exec.yaml
crond -b -l 8
exec mosdns start --dir /etc/mosdns --config /run/mosdns/config.yaml
