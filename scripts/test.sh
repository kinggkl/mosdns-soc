#!/bin/sh
# mosdns 功能测试脚本
SERVER="${1:-127.0.0.1}"
PASS=0; FAIL=0

check() { local d=$1; local t=$2; local r=$(dig @$SERVER $d $t +short 2>/dev/null | head -1)
  if [ -n "$r" ]; then PASS=$((PASS+1)); echo "  ✓ $d"; else FAIL=$((FAIL+1)); echo "  ✗ $d FAIL"; fi; }

check_reject() { local d=$1
  local r=$(dig @$SERVER $d 2>&1 | grep -c NXDOMAIN)
  if [ "$r" -gt 0 ]; then PASS=$((PASS+1)); echo "  ✓ $d (NXDOMAIN)"; else FAIL=$((FAIL+1)); echo "  ✗ $d FAIL"; fi; }

echo "=== 国内 ==="
for d in www.baidu.com www.qq.com www.taobao.com www.jd.com www.bilibili.com; do check $d A; done

echo "=== 国外 ==="
for d in www.google.com www.youtube.com www.github.com cloudflare.com; do check $d A; done

echo "=== 广告拦截 ==="
for d in ad.doubleclick.net pagead2.googlesyndication.com doubleclick.net; do check_reject $d; done

echo "=== GFW ==="
for d in twitter.com telegram.org www.facebook.com; do check $d A; done

echo "=== 预处理 ==="
# qtype65
r=$(dig @$SERVER www.baidu.com TYPE65 2>&1 | grep -c NXDOMAIN)
[ "$r" -gt 0 ] && { PASS=$((PASS+1)); echo "  ✓ qtype65→NXDOMAIN"; } || { FAIL=$((FAIL+1)); echo "  ✗ qtype65 FAIL"; }
# PTR
r=$(dig @$SERVER -x 8.8.8.8 +short 2>/dev/null | head -1)
[ -n "$r" ] && { PASS=$((PASS+1)); echo "  ✓ PTR 8.8.8.8→$r"; } || { FAIL=$((FAIL+1)); echo "  ✗ PTR FAIL"; }

echo ""
echo "=== 结果: $PASS 通过 / $FAIL 失败 ==="
