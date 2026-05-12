#!/bin/sh
# 更新规则文件：下载 Loyalsoldier dat → v2dat 解包
set -e
cd "$(dirname "$0")/dat"

echo ">>> 下载 geoip.dat + geosite.dat ..."
curl -sL -o geoip.dat   https://github.com/Loyalsoldier/v2ray-rules-dat/releases/latest/download/geoip.dat
curl -sL -o geosite.dat https://github.com/Loyalsoldier/v2ray-rules-dat/releases/latest/download/geosite.dat

echo ">>> 解包 6 分类 ..."
./v2dat unpack geoip  -o . -f "private" geoip.dat
./v2dat unpack geoip  -o . -f "cn" geoip.dat
./v2dat unpack geosite -o . -f "cn" geosite.dat
./v2dat unpack geosite -o . -f "gfw" geosite.dat
./v2dat unpack geosite -o . -f "category-ads-all" geosite.dat
./v2dat unpack geosite -o . -f "geolocation-!cn" geosite.dat

echo ">>> 完成"
ls -lh geoip_cn.txt geosite_cn.txt geosite_category-ads-all.txt geosite_gfw.txt geosite_geolocation-!cn.txt geoip_private.txt
