#!/bin/sh
set -eu

server=${1:-127.0.0.1}
port=${2:-53}
mode=${3:-}
failures=0

query() {
    dig "@$server" -p "$port" "$1" "$2" "$3" +time=2 +tries=1 +noall +comments +answer +authority +additional
}

check_address() {
    response=$(query "$1" A "+notcp") || response=
    if printf '%s\n' "$response" | awk '$4 == "A" { found = 1 } END { exit !found }'; then
        printf 'OK %s A\n' "$1"
    else
        printf 'FAIL %s A\n' "$1" >&2
        failures=$((failures + 1))
    fi
}

check_empty() {
    response=$(query "$1" "$2" "$3") || response=
    if printf '%s\n' "$response" | grep -Eq "status: $4," &&
        printf '%s\n' "$response" | grep -Eq 'ANSWER: 0,' &&
        ! printf '%s\n' "$response" | awk '$4 ~ /^(AAAA|SVCB|HTTPS)$/ { found = 1 } END { exit !found }'
    then
        printf 'OK %s %s %s\n' "$1" "$2" "$3"
    else
        printf 'FAIL %s %s %s\n%s\n' "$1" "$2" "$3" "$response" >&2
        failures=$((failures + 1))
    fi
}

for transport in +notcp +tcp; do
    check_empty example.com AAAA "$transport" NOERROR
    check_empty example.com TYPE64 "$transport" NOERROR
    check_empty example.com TYPE65 "$transport" NXDOMAIN
done

if [ "$mode" != --ipv4-policy ]; then
    for domain in www.baidu.com www.qq.com www.taobao.com www.jd.com www.bilibili.com \
        www.google.com www.youtube.com www.github.com cloudflare.com twitter.com telegram.org www.facebook.com
    do
        check_address "$domain"
    done
    for domain in ad.doubleclick.net pagead2.googlesyndication.com doubleclick.net; do
        check_empty "$domain" A "+notcp" NXDOMAIN
    done
    response=$(query 8.8.8.8.in-addr.arpa PTR "+notcp") || response=
    if ! printf '%s\n' "$response" | awk '$4 == "PTR" { found = 1 } END { exit !found }'; then
        printf 'FAIL PTR 8.8.8.8\n' >&2
        failures=$((failures + 1))
    fi
fi
[ "$failures" -eq 0 ]
