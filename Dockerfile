FROM golang:1.26.11-bookworm AS builder
ENV CGO_ENABLED=0 GOTOOLCHAIN=local

WORKDIR /src/mosdns
RUN git clone --depth 1 --branch v5.3.4 https://github.com/IrineSistiana/mosdns.git . \
    && test "$(git rev-parse HEAD)" = b7323188bab1ea742538aeccb31b692bc4967d1b
COPY build/ipv4_only*.go ./plugin/executable/sequence/
RUN go get golang.org/x/net@v0.62.0 golang.org/x/crypto@v0.59.0 github.com/quic-go/quic-go@v0.59.1 \
    github.com/klauspost/compress@v1.20.2 github.com/go-chi/chi/v5@v5.3.0 github.com/miekg/dns@v1.1.72 \
    && go test ./plugin/executable/sequence -run '^TestIPv4Only' \
    && go build -trimpath -ldflags '-s -w -X main.version=v5.3.4-soc' -o /out/mosdns .

WORKDIR /src/v2dat
RUN git init . \
    && git fetch --depth 1 https://github.com/urlesistiana/v2dat.git 47b8ee51fb528e11e1a83453b7e767a18d20d1f7 \
    && git checkout --detach FETCH_HEAD \
    && go get google.golang.org/protobuf@v1.36.11 \
    && go build -trimpath -ldflags '-s -w' -o /out/v2dat .

FROM alpine:3.24.4
RUN apk add --no-cache ca-certificates curl dcron gettext-envsubst tzdata util-linux-misc

COPY --from=builder /out/mosdns /out/v2dat /usr/local/bin/
COPY config/config.yaml config/dat_exec.yaml config/dns.yaml.tpl /etc/mosdns/
COPY config/crontab /etc/crontabs/root
COPY --chmod=755 scripts/update-rules.sh /usr/local/bin/update-rules.sh
COPY --chmod=755 entrypoint.sh /entrypoint.sh

ARG RULES_RELEASE=202611172204
RUN RULES_DATA_DIR=/usr/share/mosdns-rules /usr/local/bin/update-rules.sh "$RULES_RELEASE"

EXPOSE 53/udp 53/tcp
ENTRYPOINT ["/entrypoint.sh"]
