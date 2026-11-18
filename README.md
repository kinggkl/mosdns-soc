# mosdns SoC — Standardized Split-DNS Deployment

Production-ready [mosdns v5.3.4](https://github.com/IrineSistiana/mosdns) deployment with Docker Compose — **split-DNS + anti-pollution + ad blocking + ECS optimization + protocol redundancy**.

[中文文档](README_CN.md)

## Quick Start

```bash
git clone https://github.com/kinggkl/mosdns-soc.git
cd mosdns-soc
cp .env.example .env              # Optional configuration
make deploy                       # Build, verify bundled rules, and start
```

## Split-DNS Architecture

```
DNS Request → :53
  ├─ pre_sequence (preprocessing)
  │   AAAA/SVCB → empty | HTTPS → reject | invalid qname → reject | PTR/ANY → foreign | private IP → LAN
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
| Multi-upstream | DoH + DoT `concurrent:3` |
| Dual cache | LAN 8K + WAN 128K, lazy TTL 86400s |
| TTL grading | pre=3600s / main=300s |
| Config split | 3-file `include` architecture |

## Environment Variables (`.env`)

| Variable | Default | Description |
|----------|---------|-------------|
| `DNS_LISTEN` | `:53` | DNS listen address and port |
| `ECS_PRESET` | (empty) | Domestic ECS preset IP, leave empty to disable |
| `LOG_LEVEL` | `debug` | Log level |
| `CACHE_WAN_SIZE` | `131072` | WAN cache size |

## Operations

```bash
make test           # Functional tests
make update-rules   # Update rules and reload the container
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

The image contains a validated seed release of [Loyalsoldier rules](https://github.com/Loyalsoldier/v2ray-rules-dat). The container checks daily at 03:00 Asia/Shanghai time. It verifies both asset checksums and unpacks all six rule files before switching the active snapshot. The previous snapshot is retained. For a manual update, run:

```bash
make update-rules
```

## Image maintenance

The image builds the pinned mosdns v5.3.4 source with targeted Go dependency updates and packages it on Alpine 3.24. It builds v2dat from a pinned source commit with an updated protobuf dependency. GitHub Actions builds the Compose image, checks DNS over UDP and TCP, and reports known Go vulnerabilities found in both resulting binaries.

## IPv6 policy

AAAA and SVCB queries return NOERROR with an empty answer. HTTPS queries return NXDOMAIN. Other responses are filtered for AAAA, SVCB, and HTTPS records across all record sections, including ANY responses. A and PTR still use the existing routing. Enabling IPv6 requires an explicit policy change.

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
