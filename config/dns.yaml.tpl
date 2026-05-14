# ============================================================
# dns.yaml.tpl — 上游 DNS / ECS / Reject（模板，由 entrypoint envsubst 渲染）
# DoH + DoT 并发，仅 IPv4
# 2026-05-13: 优化 — 去 dial_addr，Cloudflare 主/Google 备
# ============================================================

plugins:
  # ── Cloudflare DoH + DoT（主，avg 7ms）──
  - tag: cloudflare
    type: forward
    args:
      concurrent: 3
      upstreams:
        - addr: "https://cloudflare-dns.com/dns-query"
        - addr: "tls://1dot1dot1dot1.cloudflare-dns.com"
          enable_pipeline: true

  # ── Google DoH + DoT（备，avg 17ms）──
  - tag: google
    type: forward
    args:
      concurrent: 3
      upstreams:
        - addr: "https://dns.google/dns-query"
        - addr: "tls://dns.google"
          enable_pipeline: true

  # ── 国外回退：Cloudflare → Google ──
  - tag: dns_nocn
    type: fallback
    args:
      primary: cloudflare
      secondary: google
      threshold: 500
      always_standby: true

  # ── AliDNS DoH + DoT（v4，国内主）──
  - tag: ali
    type: forward
    args:
      concurrent: 3
      upstreams:
        - addr: "https://dns.alidns.com/dns-query"
        - addr: "tls://dns.alidns.com"
          enable_pipeline: true
          insecure_skip_verify: true

  # ── DNSPod DoH + DoT（v4，国内备）──
  - tag: dnspod
    type: forward
    args:
      concurrent: 3
      upstreams:
        - addr: "https://doh.pub/dns-query"
        - addr: "tls://dot.pub"
          enable_pipeline: true

  # ── 国内回退：AliDNS → DNSPod ──
  - tag: dns_cn
    type: fallback
    args:
      primary: ali
      secondary: dnspod
      threshold: 500
      always_standby: true

  # ── ECS 处理 ──
  - tag: no_ecs
    type: ecs_handler
    args:
      forward: false
      preset: ""
      send: false
      mask4: 24
      mask6: 48

  - tag: ecs_cn
    type: ecs_handler
    args:
      forward: false
      preset: "${ECS_PRESET}"
      send: false
      mask4: 24
      mask6: 48

  # ── Reject 响应 ──
  - tag: reject_3
    type: sequence
    args:
      - exec: reject 3
