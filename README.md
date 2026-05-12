# mosdns SoC — 标准化 DNS 分流部署

基于 [mosdns v5.3.4](https://github.com/IrineSistiana/mosdns) 的标准化 Docker Compose 部署方案，可实现 **DNS 分流 + 反污染 + 广告拦截 + ECS 优化**。

## 快速部署

```bash
git clone https://github.com/kinggkl/mosdns-soc.git
cd mosdns-soc
cp .env.example .env          # 编辑 .env 填入 ECS_PRESET（可选）
make deploy                   # 自动下载规则 + 构建 + 启动
```

## 分流架构

```
DNS Request → :53
  ├─ pre_sequence (预处理)
  │   qtype65 → reject | 无效域名 → reject | PTR/ANY → 国外 | private IP → LAN
  └─ main_sequence (主流程)
      ad → reject NXDOMAIN (µs 级)
      cache_wan (131K) → hit → accept
      gfw → dns_nocn(Google→Cloudflare) → resp_ip 反污染     ← 优先匹配
      !cn → dns_nocn(Google→Cloudflare) → resp_ip 反污染
      cn  → ECS → dns_cn(Ali→DNSPod) → resp_ip 反污染        ← 纯国内域名
      fallthrough → 优先无污染上游

> ⚠️ 匹配顺序至关重要：`gfw/!cn` 必须在 `cn` 之前。
> Loyalsoldier 规则集中有 **158 个域名同时存在于国内和非国内列表**（如 Google 服务、米哈游游戏、阿里云等），
> 若 `cn` 优先则会误入国内 DNS，存在污染风险。当前顺序已修复。
```

## 特性

| 特性 | 实现 |
|------|------|
| 反污染 | `resp_ip` 国内/国外 IP 校验 + `drop_resp` |
| ECS 优化 | 可配置 `ECS_PRESET`（`.env` 控制） |
| 广告拦截 | 173K 规则 (`geosite_category-ads-all`) |
| 多上游并发 | DoH+DoT `concurrent:3` (v4 only) |
| 双缓存 | LAN 8K + WAN 128K，lazy TTL 86400s |
| TTL 分级 | pre=3600s / main=300s |
| 配置拆分 | `include` 3 文件 |

## 环境变量 (`.env`)

| 变量 | 默认 | 说明 |
|------|------|------|
| `ECS_PRESET` | (空) | 国内 ECS 预设 IP，留空禁用 |
| `LOG_LEVEL` | `debug` | 日志级别 |
| `CACHE_WAN_SIZE` | `131072` | WAN 缓存大小 |

## 运维命令

```bash
make test           # 功能测试
make update-rules   # 更新规则文件并重建
make clean          # 停止并清理

# 查看日志
docker logs mosdns --tail 50 -f

# 压测 (需 dnsperf)
make bench
```

## 目录结构

```
mosdns-soc/
├── .env.example          # 环境变量模板
├── docker-compose.yml    # Docker Compose
├── Dockerfile            # 镜像构建
├── entrypoint.sh         # envsubst + crond + start
├── Makefile              # 快捷命令
├── config/
│   ├── config.yaml       # 主配置
│   ├── dns.yaml.tpl      # 上游+ECS 模板
│   └── dat_exec.yaml     # 数据源+缓存+分流
├── rules/
│   ├── update.sh         # 规则更新脚本
│   └── dat/              # 规则文件 (6 分类)
├── scripts/
│   ├── deploy.sh         # 一键部署
│   └── test.sh           # 功能测试
└── custom/
    ├── reject.txt        # 自定义拦截
    └── direct.txt        # 自定义直连
```

## 依赖

- Docker 24+ / Docker Compose 2+
- 端口 53/udp + 53/tcp 可用
- 国际网络环境（需访问 Google/AliDNS/Cloudflare DoH）

## 规则更新

规则来自 [Loyalsoldier/v2ray-rules-dat](https://github.com/Loyalsoldier/v2ray-rules-dat)，通过 v2dat 解包 6 个分类。定期更新：

```bash
make update-rules
```

## 许可证

MIT
