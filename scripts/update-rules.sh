#!/bin/sh
# update-rules.sh — Loyalsoldier 规则自动更新
# 由 dcron 定时触发，运行在容器内
set -e

DAT_DIR="/etc/mosdns/dat"
LOG="/etc/mosdns/cache/update.log"

GEOIP_URL="https://github.com/Loyalsoldier/v2ray-rules-dat/releases/latest/download/geoip.dat"
GEOSITE_URL="https://github.com/Loyalsoldier/v2ray-rules-dat/releases/latest/download/geosite.dat"

log() { echo "$(date '+%Y-%m-%d %H:%M:%S') $1" | tee -a "$LOG"; }

cd "$DAT_DIR"

log "Checking for rule updates..."

# 下载（-z 检查 If-Modified-Since，无更新则 304 → 空文件）
curl -sL -o geoip.dat.new -z geoip.dat "$GEOIP_URL"
curl -sL -o geosite.dat.new -z geosite.dat "$GEOSITE_URL"

GEOIP_NEW=false
GEOSITE_NEW=false
[ -s geoip.dat.new ] && GEOIP_NEW=true
[ -s geosite.dat.new ] && GEOSITE_NEW=true

if ! $GEOIP_NEW && ! $GEOSITE_NEW; then
    log "No updates available"
    rm -f geoip.dat.new geosite.dat.new
    exit 0
fi

# 验证下载完整性（正常的 dat 文件 >1MB）
for f in geoip.dat.new geosite.dat.new; do
    if [ -f "$f" ]; then
        SIZE=$(wc -c < "$f")
        if [ "$SIZE" -lt 1000000 ]; then
            log "ERROR: $f too small (${SIZE} bytes), aborting"
            rm -f geoip.dat.new geosite.dat.new
            exit 1
        fi
    fi
done

# 替换旧文件
if $GEOIP_NEW; then
    mv geoip.dat geoip.dat.bak 2>/dev/null || true
    mv geoip.dat.new geoip.dat
    log "Updated: geoip.dat"
fi
if $GEOSITE_NEW; then
    mv geosite.dat geosite.dat.bak 2>/dev/null || true
    mv geosite.dat.new geosite.dat
    log "Updated: geosite.dat"
fi

# 解包 6 个分类
log "Unpacking rules..."
./v2dat unpack geoip  -o . -f "private" geoip.dat             || { log "FAIL: unpack geoip_private"; exit 1; }
./v2dat unpack geoip  -o . -f "cn" geoip.dat                  || { log "FAIL: unpack geoip_cn"; exit 1; }
./v2dat unpack geosite -o . -f "cn" geosite.dat               || { log "FAIL: unpack geosite_cn"; exit 1; }
./v2dat unpack geosite -o . -f "gfw" geosite.dat              || { log "FAIL: unpack geosite_gfw"; exit 1; }
./v2dat unpack geosite -o . -f "category-ads-all" geosite.dat || { log "FAIL: unpack geosite_ads"; exit 1; }
./v2dat unpack geosite -o . -f "geolocation-!cn" geosite.dat  || { log "FAIL: unpack geosite_!cn"; exit 1; }

log "Update complete. Restarting mosdns..."
sync
sleep 1

# 触发 Docker 重启（restart: always 策略自动恢复）
kill -TERM 1