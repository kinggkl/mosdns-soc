# mosdns SoC — Standardized Split-DNS Deployment

Production-ready [mosdns v5.3.4](https://github.com/IrineSistiana/mosdns) deployment with Docker Compose — **split-DNS + anti-pollution + ad blocking + ECS optimization + protocol redundancy**.

[中文文档](README_CN.md)

## Quick Start

```bash
git clone https://github.com/kinggkl/mosdns-soc.git
cd mosdns-soc
cp .env.example .env              # Edit .env to set ECS_PRESET (optional)
make deploy                       # Download rules + build + start
```

## Split-DNS Architecture

```
DNS Request → :53
  ├─ pre_sequence (preprocessing)
  │   qtype65 → reject | invalid qname → reject | PTR/ANY → foreign | private IP → LAN
  └─ main_sequence (routing)
      ad → reject NXDOMAIN (µs-level)
      cache_wan (128K) → hit → accept
      gfw → dns_nocn(Cloudflare→Google) → resp_ip anti-pollution      ← priority match
      !cn → dns_nocn(Cloudflare→Google) → resp_ip anti-pollution
      cn  → ECS → dns_cn(Ali→DNSPod) → resp_ip anti-pollution         ← domestic only
      fallthrough → prefer clean upstream

> ⚠️ Match order is critical: `gfw/!cn` MUST precede `cn`.
> Loyalsoldier rules have 158 overlapping domains across domestic and non-domestic lists
> (e.g., Google services, Mihoyo games, Alibaba Cloud). CN-first order risks pollution.

## Upstream Design (v2026-05-13)

| Tier | Provider | Role | Protocols | Avg Latency |
|------|----------|------|-----------|:-----------:|
| Foreign Primary | Cloudflare | DoH + DoT | `https://` `tls://` | **7ms** |
| Foreign Secondary | Google | DoH + DoT | `https://` `tls://` | 17ms |
| Domestic Primary | AliDNS | DoH + DoT | `https://` `tls://` | — |
| Domestic Secondary | DNSPod | DoH + DoT | `https://` `tls://` | — |

**Design decisions (2026-05-13):**
- **`dial_addr` removed** — DNS domains already resolve to multiple IPs naturally (`cloudflare-dns.com` → 4 IPs). Forcing `dial_addr` to anycast IPs for DoH causes incorrect responses (port 443 does not serve the DoH endpoint).
- **Cloudflare primary** — 2.4x lower latency than Google on this network (7ms vs 17ms avg).
- **Protocol redundancy** — DoH + DoT per upstream. DNS-over-QUIC (DoQ) excluded: mainstream providers do not support it yet. HTTP/3 evaluated but offers no latency benefit over HTTP/2 on this network.
- **Single `addr` per protocol** — unnecessary duplication removed. DNS resolution already provides multi-IP diversity.

## Features

| Feature | Implementation |
|---------|---------------|
| Anti-pollution | `resp_ip` domestic/foreign IP verification + `drop_resp` |
| ECS optimization | Configurable `ECS_PRESET` (via `.env`) |
| Ad blocking | 173K rules (`geosite_category-ads-all`) |
| Multi-upstream | DoH + DoT `concurrent:3` (IPv4 only) |
| Dual cache | LAN 8K + WAN 128K, lazy TTL 86400s |
| TTL grading | pre=3600s / main=300s |
| Config split | 3-file `include` architecture |

## Environment Variables (`.env`)

| Variable | Default | Description |
|----------|---------|-------------|
| `ECS_PRESET` | (empty) | Domestic ECS preset IP, leave empty to disable |
| `LOG_LEVEL` | `debug` | Log level |
| `CACHE_WAN_SIZE` | `131072` | WAN cache size |

## Operations

```bash
make test           # Functional tests
make update-rules   # Update rule files and rebuild
make clean          # Stop and clean up

# View logs
docker logs mosdns --tail 50 -f

# Stress test (requires dnsperf)
make bench
```

## Directory Structure

```
mosdns-soc/
├── .env.example              # Environment template
├── docker-compose.yml        # Docker Compose
├── Dockerfile                # Image build
├── entrypoint.sh             # envsubst + crond + start
├── Makefile                  # Shortcut commands
├── config/
│   ├── config.yaml           # Main config
│   ├── dns.yaml.tpl          # Upstream + ECS template
│   └── dat_exec.yaml         # Data + cache + routing
├── rules/
│   ├── update.sh             # Rule update script
│   └── dat/                  # Rule files (6 categories)
├── scripts/
│   ├── deploy.sh             # One-click deploy
│   └── test.sh               # Functional tests
├── benchmarks/
│   └── 2026-05-13.md         # Latest benchmark results
└── custom/
    ├── reject.txt             # Custom blocklist
    └── direct.txt             # Custom allowlist
```

## Prerequisites

- Docker 24+ / Docker Compose 2+
- Port 53/udp + 53/tcp available
- International network access (Google/AliDNS/Cloudflare DoH reachable)

## Rule Updates

Rules sourced from [Loyalsoldier/v2ray-rules-dat](https://github.com/Loyalsoldier/v2ray-rules-dat), unpacked via v2dat into 6 categories. Update periodically:

```bash
make update-rules
```

## Benchmark (2026-05-13)

| Metric | Value |
|--------|-------|
| QPS ceiling | ~30,000/s |
| Average latency | 3ms (cache-hit: 30µs) |
| Ad block latency | ~20µs |
| CPU utilization | <1% (post-warmup) |
| Memory (pre-warmup) | ~70MB |
| Memory (5.8M queries) | ~130MB |

### Protocol Latency Comparison (Cloudflare DNS)

| Protocol | baidu.com | google.com | facebook.com | Avg |
|----------|:---:|:---:|:---:|:---:|
| DoT (`tls://`) | 6ms | 8ms | 6ms | **7ms** |
| HTTP/2 (`https://`) | 34ms | 36ms | 37ms | 36ms |
| HTTP/3 (`h3://`) | 42ms | 37ms | 37ms | 39ms |

### Anti-Pollution Verification

| Domain | mosdns | ASN | Clean? |
|--------|--------|-----|:---:|
| facebook.com | 57.145.12.1 | AS32934 Meta (HK CDN) | ✅ |
| twitter.com | 162.159.140.229 | AS13335 Cloudflare | ✅ |
| google.com | 142.250.199.206 | AS15169 Google (US) | ✅ |

## License

MIT
