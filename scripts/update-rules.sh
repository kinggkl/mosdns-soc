#!/bin/sh
set -eu

data_dir=${RULES_DATA_DIR:-/etc/mosdns/dat}
repository=https://github.com/Loyalsoldier/v2ray-rules-dat
mode=${1:-latest}
mkdir -p "$data_dir"
cd "$data_dir"
exec 9>.update.lock
flock 9

if [ "$mode" = --seed ] && [ -s current/version ]; then
    exit 0
fi

stage=$(mktemp -d .update.XXXXXX)
trap 'rm -rf "$stage"' EXIT
trap 'exit 1' HUP INT TERM

case "$mode" in
    --seed)
        cp -R /usr/share/mosdns-rules/current/. "$stage/"
        release=$(cat "$stage/version")
        ;;
    latest|--restart)
        location=$(curl -fsSL --retry 3 --max-time 60 -o /dev/null -w '%{url_effective}' "$repository/releases/latest")
        release=${location##*/}
        ;;
    *)
        release=$mode
        ;;
esac

case "$release" in
    ''|*[!0-9]*) echo "Invalid rules release: $release" >&2; exit 1 ;;
esac
[ "${#release}" -eq 12 ] || { echo "Invalid rules release: $release" >&2; exit 1; }

previous=
if [ -s current/version ]; then
    previous=$(cat current/version)
    if [ "$previous" -ge "$release" ]; then
        printf 'Rules already current: %s\n' "$previous"
        exit 0
    fi
fi

if [ "$mode" != --seed ]; then
    (
        cd "$stage"
        for asset in geoip.dat geosite.dat; do
            url="$repository/releases/download/$release/$asset"
            curl -fsSL --retry 3 --max-time 120 -o "$asset" "$url"
            curl -fsSL --retry 3 --max-time 60 -o "$asset.sha256sum" "$url.sha256sum"
            sha256sum -c "$asset.sha256sum"
        done
        v2dat unpack geoip -f private -f cn geoip.dat
        v2dat unpack geosite -f cn -f gfw -f category-ads-all -f 'geolocation-!cn' geosite.dat
        rm geoip.dat geosite.dat geoip.dat.sha256sum geosite.dat.sha256sum
        printf '%s\n' "$release" >version
    )
fi

for rule in geoip_private geoip_cn geosite_cn geosite_gfw geosite_category-ads-all 'geosite_geolocation-!cn'; do
    [ -s "$stage/$rule.txt" ] || { echo "Missing rule: $rule" >&2; exit 1; }
done

snapshot="rules-$release"
if [ -e "$snapshot" ]; then
    # A prior run may have stopped between publishing the directory and its symlink.
    rm -rf "$snapshot"
fi
mv "$stage" "$snapshot"
mkdir "$stage"
ln -s "$snapshot" "$stage/current"
mv -Tf "$stage/current" current

# Keep the previous release available for rollback.
for path in rules-????????????; do
    if [ -d "$path" ] && [ "$path" != "$snapshot" ] && [ "$path" != "rules-$previous" ]; then
        rm -rf "$path"
    fi
done

printf 'Activated rules release %s\n' "$release"
if [ "$mode" = --restart ]; then
    kill -TERM 1
fi
