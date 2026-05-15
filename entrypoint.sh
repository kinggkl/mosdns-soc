#!/bin/sh
# mosdns entrypoint — v2.1
# 启动 dcron（规则自动更新）+ mosdns
crond -b -l 8
exec /usr/bin/mosdns start --dir /etc/mosdns