# ============================================================
# dns.yaml.tpl — 上游 DNS / ECS / Reject（模板，由 entrypoint envsubst 渲染）
# DoH + DoT 并发，仅 IPv4
# ============================================================

plugins:
  # ── Google DoH + DoT（v4 多地址并发）──
  - tag: google
    type: forward
    args:
      concurrent: 3
      upstreams:
        - addr: "https://dns.google/dns-query"
          dial_addr: "8.8.8.8"
        - addr: "https://dns.google/dns-query"
          dial_addr: "8.8.4.4"
        - addr: "tls://dns.google"
          dial_addr: "8.8.8.8"
          enable_pipeline: true
        - addr: "tls://dns.google"
          dial_addr: "8.8.4.4"
          enable_pipeline: true

  # ── Cloudflare DoH + DoT（v4，备用）──
  - tag: cloudflare
    type: forward
    args:
      concurrent: 3
      upstreams:
        - addr: "https://cloudflare-dns.com/dns-query"
          dial_addr: "1.1.1.1"
        - addr: "https://cloudflare-dns.com/dns-query"
          dial_addr: "1.0.0.1"
        - addr: "tls://1dot1dot1dot1.cloudflare-dns.com"
          dial_addr: "1.1.1.1"
          enable_pipeline: true
        - addr: "tls://1dot1dot1dot1.cloudflare-dns.com"
          dial_addr: "1.0.0.1"
          enable_pipeline: true

  # ── 国外回退：Google → Cloudflare ──
  - tag: dns_nocn
    type: fallback
    args:
      primary: google
      secondary: cloudflare
      threshold: 500
      always_standby: true

  # ── AliDNS DoH + DoT（v4）──
  - tag: ali
    type: forward
    args:
      concurrent: 3
      upstreams:
        - addr: "https://dns.alidns.com/dns-query"
          dial_addr: "223.5.5.5"
        - addr: "https://dns.alidns.com/dns-query"
          dial_addr: "223.6.6.6"
        - addr: "tls://dns.alidns.com"
          dial_addr: "223.5.5.5"
          enable_pipeline: true
          insecure_skip_verify: true
        - addr: "tls://dns.alidns.com"
          dial_addr: "223.6.6.6"
          enable_pipeline: true
          insecure_skip_verify: true

  # ── DNSPod DoH + DoT（v4，国内备用）──
  - tag: dnspod
    type: forward
    args:
      concurrent: 3
      upstreams:
        - addr: "https://doh.pub/dns-query"
          dial_addr: "120.53.53.53"
        - addr: "tls://dot.pub"
          dial_addr: "1.12.12.12"
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
