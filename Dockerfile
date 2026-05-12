FROM irinesistiana/mosdns:v5.3.4
LABEL maintainer="mosdns-soc"

COPY config/config.yaml /etc/mosdns/config.yaml
COPY config/dat_exec.yaml /etc/mosdns/dat_exec.yaml
COPY config/dns.yaml.tpl /etc/mosdns/dns.yaml.tpl
COPY entrypoint.sh /entrypoint.sh
COPY rules/dat /etc/mosdns/dat

RUN chmod a+x /entrypoint.sh

VOLUME /etc/mosdns
EXPOSE 53/udp 53/tcp
ENTRYPOINT [ "/entrypoint.sh" ]
