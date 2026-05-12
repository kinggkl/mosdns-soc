#!/bin/sh
# mosdns 一键部署
set -e
cd "$(dirname "$0")/.."

# 检查 .env
if [ ! -f .env ]; then
  echo ">>> 创建 .env（从 .env.example）"
  cp .env.example .env
  echo "请编辑 .env 填入 ECS_PRESET 后重新运行"
  exit 1
fi

# 检查规则文件
if [ ! -f rules/dat/geosite_cn.txt ]; then
  echo ">>> 下载规则文件 ..."
  bash rules/update.sh
fi

# 构建并启动
echo ">>> Docker Compose 构建 & 启动 ..."
docker compose build
docker compose up -d

echo ">>> mosdns 已部署"
docker ps --format "table {{.Names}}\t{{.Status}}" | grep mosdns
