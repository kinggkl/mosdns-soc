#!/bin/sh
# mosdns entrypoint — 环境变量注入 + crond + 启动

# 用环境变量替换配置模板
if [ -f /etc/mosdns/dns.yaml.tpl ]; then
  envsubst < /etc/mosdns/dns.yaml.tpl > /etc/mosdns/dns.yaml
fi

/usr/sbin/crond -b -l 8
exec /usr/bin/mosdns start --dir /etc/mosdns
