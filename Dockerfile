# ============================================================
# mosdns v5.3.4 Dockerfile — v2.2 (auto-update + timezone fix)
# 新增：dcron + update-rules.sh 规则自动更新 + tzdata 时区
# 参考：Jasper-1024/mosdns_v5 + Loyalsoldier/v2ray-rules-dat
# ============================================================

FROM irinesistiana/mosdns:v5.3.4
LABEL maintainer="mosdns-v5"

# 安装 dcron（轻量 cron，~100KB）+ curl（下载规则文件）+ tzdata（时区支持）
RUN apk add --no-cache dcron curl tzdata

COPY ./config.yaml /etc/mosdns/config.yaml
COPY ./dat_exec.yaml /etc/mosdns/dat_exec.yaml
COPY ./dns.yaml /etc/mosdns/dns.yaml
COPY ./entrypoint.sh /entrypoint.sh
COPY ./update-rules.sh /usr/local/bin/update-rules.sh
COPY ./crontab /etc/crontabs/root
COPY ./dat /etc/mosdns/dat

RUN chmod a+x /entrypoint.sh /usr/local/bin/update-rules.sh

VOLUME /etc/mosdns
EXPOSE 53/udp 53/tcp
ENTRYPOINT [ "/entrypoint.sh" ]