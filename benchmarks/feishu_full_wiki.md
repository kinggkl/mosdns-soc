# mosdns v5.3.4 标准化 DNS 分流部署

> 潘先生的个人知识库 · 网络基础设施 · DNS
> 
> GitHub: https://github.com/kinggkl/mosdns-soc
> 部署位置: 192.168.188.249:/opt/mosdns/

---

## 一、项目概述

基于 [mosdns v5.3.4](https://github.com/IrineSistiana/mosdns) 的生产级 Docker Compose 标准化交付方案。实现 **DNS 分流 + 反污染 + 广告拦截 + ECS 优化 + 协议冗余**。

### 核心特性

| 特性 | 实现方式 |
|------|----------|
| 反污染 | `resp_ip` 国内/国外 IP 校验 + `drop_resp` |
| ECS 优化 | 可配置 `ECS_PRESET`（.env 控制） |
| 广告拦截 | 173K 规则 (`geosite_category-ads-all`) |
| 多上游并发 | DoH + DoT `concurrent:3` (仅 IPv4) |
| 双缓存 | LAN 8K + WAN 128K，lazy TTL 86400s |
| TTL 分级 | pre=3600s / main=300s |
| 配置拆分 | `include` 三文件架构（config / dns / dat_exec） |
| 预处理 | qtype65 reject / qtype12&255 → 国外 / PTR private → LAN |
| 规则来源 | Loyalsoldier/v2ray-rules-dat，v2dat 解包 6 分类 |

### 部署环境

| 项目 | 详情 |
|------|------|
| 机器 | Debian 13, 192.168.188.249 |
| CPU | Intel Xeon Platinum 8352Y (1 vCPU) |
| 内存 | 7.8GB |
| Docker | Docker Compose, network_mode=host |
| 端口 | 53/udp + 53/tcp + 8080 (管理) |

---

## 二、分流架构

```
DNS Request → :53
  ├─ pre_sequence (预处理)
  │   qtype65 → reject | 无效域名 → reject
  │   qtype12/255 → no_ecs + dns_nocn (TTL 1h)
  │   PTR private IP → cache_lan + dns_cn
  │   else → jump has_resp_pre (进入缓存检查)
  │
  └─ main_sequence (主流程)
      ad → reject NXDOMAIN (µs 级)
      cache_wan (128K) → hit → accept (TTL 5m)
      
      gfw → dns_nocn(Cloudflare→Google) → resp_ip 反污染     ← 优先匹配！
      !cn → dns_nocn(Cloudflare→Google) → resp_ip 反污染
      cn  → ECS → dns_cn(AliDNS→DNSPod) → resp_ip 反污染      ← 纯国内
      
      fallthrough → 优先无污染上游
```

> ⚠️ **匹配顺序至关重要**：`gfw/!cn` 必须在 `cn` 之前。Loyalsoldier 规则集中有 **158 个域名同时存在于国内和非国内列表**（如 Google 服务、米哈游游戏、阿里云等），cn 优先会导致被墙域名误入国内 DNS 路径。

---

## 三、上游配置演进

### v1.0 (May 12) — 初始部署

```yaml
# 国外：Google 主 + Cloudflare 备
google:
  - https://dns.google/dns-query    dial_addr: 8.8.8.8
  - https://dns.google/dns-query    dial_addr: 8.8.4.4
  - tls://dns.google               dial_addr: 8.8.8.8
  - tls://dns.google               dial_addr: 8.8.4.4

cloudflare:
  - https://cloudflare-dns.com/...   dial_addr: 1.1.1.1
  - https://cloudflare-dns.com/...   dial_addr: 1.0.0.1
  - tls://1dot1...cloudflare-dns...  dial_addr: 1.1.1.1
  - tls://1dot1...cloudflare-dns...  dial_addr: 1.0.0.1

dns_nocn: primary=google, secondary=cloudflare

# 国内：AliDNS 主 + DNSPod 备
ali:
  - https://dns.alidns.com/...      dial_addr: 223.5.5.5
  - https://dns.alidns.com/...      dial_addr: 223.6.6.6
  - tls://dns.alidns.com           dial_addr: 223.5.5.5
  - tls://dns.alidns.com           dial_addr: 223.6.6.6
```

### v1.1 (May 12) — 主流程顺序修复

**问题**：google.com 同时存在于 `geosite_cn` 和 `geosite_gfw`，原顺序先匹配 cn → 经国内 DNS → 污染 IP → drop → 二轮查询，延迟加倍。

**修复**：`main_sequence` 中 gfw/!cn 匹配移至 cn 之前。

```yaml
# ✅ 正确顺序
- matches: "qname $geosite_gfw"              # 1st: GFW → 国外
  exec: $query_nocn
- matches: "qname $geosite_location_not_cn"  # 2nd: !cn → 国外
  exec: $query_nocn
- matches: "qname $geosite_cn"               # 3rd: 纯 cn → 国内
  exec: $query_cn
```

### v2.0 (May 13) — 上游优化

| 变更 | 旧 → 新 | 原因 |
|------|---------|------|
| dial_addr | 所有上游 | **全部移除** | DNS 域名自然解析多 IP；dial_addr 导致 DoH 连接到错误端口 |
| 国外主 | Google → **Cloudflare** | 延迟优势 2.4x (7ms vs 17ms) |
| 地址数 | 每协议 ×2 → ×1 | 去重。DNS 解析已提供多 IP 冗余 (cloudflare-dns.com → 4 IPs) |

```yaml
# ✅ v2.0 最终配置
cloudflare:
  - https://cloudflare-dns.com/dns-query
  - tls://1dot1dot1dot1.cloudflare-dns.com

google:
  - https://dns.google/dns-query
  - tls://dns.google

ali:
  - https://dns.alidns.com/dns-query
  - tls://dns.alidns.com

dnspod:
  - https://doh.pub/dns-query
  - tls://dot.pub

dns_nocn: primary=cloudflare, secondary=google
dns_cn:   primary=ali, secondary=dnspod
```

---

## 四、性能基准

### 压力测试 (dnsperf, May 12)

| 指标 | 数值 |
|------|------|
| QPS 上限 | ~30,000/s（所有并发级别 50-2000 一致） |
| 完成率 | 100%（全负载级别） |
| 平均延迟 | 3ms |
| 缓存命中 | ~30µs |
| 广告拦截 | ~20µs |
| 内存（空闲） | ~70MB |
| 内存（580万查询后） | ~130MB（+57MB） |
| CPU（预热后） | <1% |

### 协议延迟对比 (May 13, Cloudflare DNS 实测)

| 协议 | baidu.com | google.com | facebook.com | **平均** |
|------|:---:|:---:|:---:|:---:|
| **DoT** (tls://) | 6ms | 8ms | 6ms | **7ms** |
| DoH (https://) | 34ms | 36ms | 37ms | 36ms |
| DoH3 (h3://) | 42ms | 37ms | 37ms | 39ms |

> DoT 比 DoH 快 5 倍。HTTP/3 在此网络无延迟优势。DoQ 未加入——主流公共 DNS 提供商均不支持。

### Cloudflare vs Google 逐域名延迟

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

### HTTP/3 支持矩阵

| 提供商 | DoH3 | DoQ | HTTP/2 | DoT |
|--------|:---:|:---:|:---:|:---:|
| Cloudflare | ✅ | ❌ | ✅ | ✅ |
| Google | ✅ | ❌ | ✅ | ✅ |
| AliDNS | ✅ | ❌ | ✅ | ✅ |
| DNSPod | ❌ | ❌ | ✅ | ✅ |

---

## 五、反污染验证

### 方法

所有 GFW 域名结果通过 **SSL 证书 + ASN + whois** 三重验证，不凭 IP 段猜测。

### 结果 (May 13)

| 域名 | mosdns 结果 | ASN | 验证方式 | 纯净? |
|------|-----------|-----|----------|:---:|
| facebook.com | 57.145.12.1 | AS32934 Meta (HK CDN) | SSL CN=*.facebook.com | ✅ |
| facebook.com | 157.240.211.35 | AS32934 Meta | SSL | ✅ |
| twitter.com | 162.159.140.229 | AS13335 Cloudflare | DoH 对比 | ✅ |
| telegram.org | 149.154.167.99 | AS62041 Telegram | DoH 对比 | ✅ |
| youtube.com | 142.250.199.206 | AS15169 Google | DoH 对比 | ✅ |

### ⚠️ IP 验证协议（核心教训）

**禁止凭 IP 段推测是否被污染。** 必须执行四步验证：

1. **SSL/TLS 证书** — `curl -k -v https://IP/` → 检查 CN
2. **ASN / ISP** — `curl ip-api.com/json/IP` → 验证组织归属
3. **反向 DNS** — `dig -x IP`
4. **HTTP/HTTPS 服务** — `curl http://IP/` → 检查响应

**案例**：facebook.com 返回 57.145.12.1（看上去像污染 IP），经验证持有有效 `*.facebook.com` 证书、AS32934 Facebook Inc.（香港 CDN 节点），确认为合法 IP。

---

## 六、dial_addr 问题分析 (May 13)

### 问题发现

mosdns 对 facebook.com 返回的 IP 与直接 DoH 查询不同，初步怀疑存在污染。

### 诊断

| 测试 | 方法 | 结果 |
|------|------|------|
| Google 明文 DNS (53) | dig @8.8.8.8 | 57.145.12.1 (合法 Meta HK CDN) |
| Google DoH (dial_addr 8.8.8.8) | curl --resolve dns.google:443:8.8.8.8 | 超时 |
| Cloudflare DoH (dial_addr 1.1.1.1) | curl --resolve cloudflare-dns.com:443:1.1.1.1 | 57.144.64.1 (合法 Meta HK CDN) |
| Cloudflare DoH (系统解析) | curl cloudflare-dns.com/dns-query | 163.70.159.35 (合法 Meta 边缘节点) |

### 根因

**1.1.1.1:443 不服务 cloudflare-dns.com 的 HTTPS 端点。** dial_addr 强制连接到了错误的服务端口。Cloudflare 的 DoH 实际运行在 104.16.248.249:443 等 CDN IP 上，而非 anycast DNS IP。

### 修复

移除所有 `dial_addr`。cloudflare-dns.com 系统解析后得到 4 个 IP（104.16.248.249、104.16.249.249、1.1.1.1、1.0.0.1），已提供充分冗余。

---

## 七、部署结构

```
/opt/mosdns/
├── .env                      # ECS_PRESET + LOG_LEVEL
├── docker-compose.yml        # network_mode=host
├── Dockerfile                # FROM irinesistiana/mosdns:v5.3.4
├── entrypoint.sh             # envsubst 渲染 + crond + mosdns start
├── Makefile                  # deploy / test / bench / update-rules / clean
├── config.yaml               # log + api:8080 + include
├── dns.yaml                  # 上游 + ECS + Reject
├── dat_exec.yaml             # 数据源 + 双缓存 + 分流序列
├── dat/                      # 规则文件 (6 分类, ~326K 行)
│   ├── geoip_cn.txt          (8,669 lines)
│   ├── geoip_private.txt     (18 lines)
│   ├── geosite_cn.txt        (113,944 lines)
│   ├── geosite_gfw.txt       (4,213 lines)
│   ├── geosite_geolocation-!cn.txt  (26,329 lines)
│   └── geosite_category-ads-all.txt (173,118 lines)
├── cache/                    # 缓存持久化 (cache.dump)
├── scripts/
│   ├── deploy.sh             # 一键下载规则 + 构建 + 启动
│   └── test.sh               # 功能测试
└── custom/
    ├── reject.txt             # 自定义拦截列表
    └── direct.txt             # 自定义直连列表
```

---

## 八、运维命令

```bash
# 部署
make deploy                   # 下载规则 + 构建 + 启动

# 测试
make test                     # 功能测试 (domestic/foreign/ad/cache)
make bench                    # dnsperf 压测 (需 apt install dnsperf)

# 维护
make update-rules             # 更新 Loyalsoldier 规则并重建
make clean                    # 停止并清理

# 监视
docker logs mosdns --tail 50 -f
curl http://localhost:8080/plugins/cache_wan/flush   # 清缓存
```

---

## 九、版本历史

| 日期 | 版本 | 内容 |
|------|------|------|
| May 12 | v1.0 | SoC 标准化交付：3 文件配置拆分、DoH+DoT 四上游、反污染、双缓存、v2dat 6 分类规则、Makefile 一键部署 |
| May 12 | v1.1 | 修复 main_sequence 匹配顺序：gfw/!cn 优先于 cn，避免 158 个重叠域名走国内路径 |
| May 13 | v2.0 | 上游优化：去 dial_addr、Cloudflare→Google 主备互换、精简协议、协议延迟对比测试、反污染 SSL/ASN 验证、EN+CN README |

---

## 十、关联资源

- GitHub 仓库: https://github.com/kinggkl/mosdns-soc
- 参考设计: [Jasper-1024/mosdns_docker](https://github.com/Jasper-1024/mosdns_docker)
- 规则来源: [Loyalsoldier/v2ray-rules-dat](https://github.com/Loyalsoldier/v2ray-rules-dat)
- mosdns 上游: [IrineSistiana/mosdns](https://github.com/IrineSistiana/mosdns)
