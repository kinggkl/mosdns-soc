# mosdns v5.3.4 上游优化与性能基准

## 变更摘要 (2026-05-13)

| 变更项 | 旧 | 新 | 原因 |
|--------|-----|-----|------|
| dial_addr | 所有上游强制指定IP | 全部移除 | DNS域名自然解析多IP，dial_addr导致DoH连接错误 |
| 国外主上游 | Google (17ms) | **Cloudflare (7ms)** | 2.4倍延迟优势 |
| 国外备上游 | Cloudflare | Google | 主备互换 |
| 协议冗余 | DoH×2 + DoT×2（多地址） | DoH×1 + DoT×1（单地址） | 消除无效重复，DNS解析已提供多IP |
| 文档 | 中文README | 英文README + 中文链接 | 国际化 |

## 架构总览

```
DNS Request → :53
  ├─ pre_sequence (预处理)
  │   qtype65 → reject | 无效域名 → reject | PTR/ANY → 国外 | private IP → LAN
  └─ main_sequence (主流程)
      ad → reject NXDOMAIN (µs 级)
      cache_wan (128K) → hit → accept
      gfw → Cloudflare(主)→Google(备) → resp_ip 反污染
      !cn → Cloudflare(主)→Google(备) → resp_ip 反污染
      cn  → ECS → AliDNS→DNSPod → resp_ip 反污染
      fallthrough → 优先无污染上游
```

## 上游配置（新）

```yaml
# Cloudflare（主，avg 7ms）
- addr: "https://cloudflare-dns.com/dns-query"       # DoH
- addr: "tls://1dot1dot1dot1.cloudflare-dns.com"     # DoT

# Google（备，avg 17ms）
- addr: "https://dns.google/dns-query"               # DoH  
- addr: "tls://dns.google"                           # DoT

# AliDNS（国内主）
- addr: "https://dns.alidns.com/dns-query"
- addr: "tls://dns.alidns.com"

# DNSPod（国内备）
- addr: "https://doh.pub/dns-query"
- addr: "tls://dot.pub"
```

> 关键变更：**去掉 dial_addr**。DNS域名已自然解析到多个IP（cloudflare-dns.com → 4个IP），不需要强制指定。dial_addr 反而会导致 DoH 请求连接到错误端口返回垃圾数据。

## 协议延迟对比（Cloudflare DNS，远程机实测）

| 协议 | baidu.com | google.com | facebook.com | **平均** |
|------|:---:|:---:|:---:|:---:|
| **DoT** (tls://) | 6ms | 8ms | 6ms | **7ms** |
| DoH (https://) | 34ms | 36ms | 37ms | 36ms |
| DoH3 (h3://) | 42ms | 37ms | 37ms | 39ms |

> DoT 比 DoH 快 5 倍。HTTP/3 在此网络无优势。DoQ（DNS-over-QUIC）未加入——主流公共DNS提供商均不支持。

## Cloudflare vs Google 逐域名延迟

| 域名 | Cloudflare | Google | 优势 |
|------|:---:|:---:|------|
| facebook.com | 4ms | 32ms | Cloudflare 8x |
| google.com | 8ms | 20ms | Cloudflare |
| youtube.com | 8ms | 20ms | Cloudflare |
| twitter.com | 8ms | 4ms | Google |
| baidu.com | 8ms | 4ms | Google |
| taobao.com | 4ms | 40ms | Cloudflare 10x |
| weixin.qq.com | 8ms | 8ms | Tie |
| github.com | 8ms | 8ms | Tie |
| **平均** | **7ms** | **17ms** | **Cloudflare 2.4x** |

## HTTP/3 支持矩阵

| 提供商 | DoH3 | DoQ | HTTP/2 | DoT |
|--------|:---:|:---:|:---:|:---:|
| Cloudflare | ✅ | ❌ | ✅ | ✅ |
| Google | ✅ | ❌ | ✅ | ✅ |
| AliDNS | ✅ | ❌ | ✅ | ✅ |
| DNSPod | ❌ | ❌ | ✅ | ✅ |

> DoQ：截至2026-05仅 Quad9 和 AdGuard 支持。

## 反污染验证

所有 GFW 域名结果通过 SSL 证书 + ASN + whois 三重验证，非凭 IP 段猜测：

| 域名 | mosdns 结果 | ASN | 验证方式 | 纯净? |
|------|-----------|-----|----------|:---:|
| facebook.com | 57.145.12.1 | AS32934 Meta | SSL CN=*.facebook.com | ✅ |
| facebook.com | 157.240.211.35 | AS32934 Meta | SSL CN=*.facebook.com | ✅ |
| twitter.com | 162.159.140.229 | AS13335 Cloudflare | DoH 对比一致 | ✅ |
| telegram.org | 149.154.167.99 | AS62041 Telegram | DoH 对比一致 | ✅ |
| youtube.com | 142.250.199.206 | AS15169 Google | DoH 对比一致 | ✅ |

## 性能基准

| 指标 | 数值 |
|------|------|
| QPS 上限 | ~30,000/s（所有并发级别一致） |
| 完成率 | 100%（50-2000客户端全级别） |
| 平均延迟 | 3ms |
| 缓存命中 | ~30µs |
| 广告拦截 | ~20µs |
| 内存（空闲） | ~70MB |
| 内存（580万查询后） | ~130MB（+57MB） |
| CPU（预热后） | <1% |

## dial_addr 问题分析

**发现问题：** 配置中 dial_addr 导致 DoH 上游返回 GFW 域名的错误响应。

**诊断过程：**

| 测试 | 方法 | 结果 |
|------|------|------|
| Google 明文 DNS (53) | dig @8.8.8.8 | facebook → 57.145.12.1 (合法 Meta HK CDN) |
| Google DoH (dial_addr 8.8.8.8) | curl --resolve dns.google:443:8.8.8.8 | 超时 |
| Cloudflare DoH (dial_addr 1.1.1.1) | curl --resolve cloudflare-dns.com:443:1.1.1.1 | facebook → 57.144.64.1 (合法 Meta HK CDN) |
| Cloudflare DoH (系统解析) | curl cloudflare-dns.com/dns-query | facebook → 163.70.159.35 (合法 Meta 边缘节点) |

**根因：** 1.1.1.1:443 不服务 cloudflare-dns.com 的 HTTPS 端点。dial_addr 强制连接到了错误的服务端口。

**修复：** 移除所有 dial_addr，由系统自然解析域名。cloudflare-dns.com 解析到 4 个 IP（104.16.248.249、104.16.249.249、1.1.1.1、1.0.0.1），已提供充分冗余。

## IP 验证协议

**核心教训：不凭 IP 段推测是否被污染。** 必须通过以下四步验证：

1. **SSL/TLS 证书** — `curl -k -v https://IP/` → 检查 CN
2. **ASN / ISP** — `curl ip-api.com/json/IP` → 验证组织归属
3. **反向 DNS** — `dig -x IP`
4. **HTTP/HTTPS 服务** — `curl http://IP/` → 检查响应

**案例：** facebook.com 返回 57.145.12.1（不常见的 IP 段），经验证持有有效 `*.facebook.com` 证书，AS32934 Facebook Inc.（香港 CDN 节点），确认为合法 IP。

## 部署验证（2026-05-13）

| 测试项 | 结果 |
|--------|:---:|
| 服务重启 | 1秒，DNS 零中断 |
| 路由（gfw→Cloudflare） | ✅ 8ms |
| 反污染（5域名） | ✅ 全部纯净 |
| 国内（3域名） | ✅ 正确ISP |
| 广告拦截 | ✅ NXDOMAIN |
| 插件加载 | ✅ 111个全部正常 |

## 代码仓库

GitHub: https://github.com/kinggkl/mosdns-soc

- README.md（英文）+ README_CN.md（中文）
- config/dns.yaml.tpl（上游配置模板）
- config/dat_exec.yaml（数据源+缓存+分流）
- benchmarks/2026-05-13.md（本次性能数据）
