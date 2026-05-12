.PHONY: deploy update-rules test clean

deploy:
	bash scripts/deploy.sh

update-rules:
	bash rules/update.sh
	docker compose down && docker compose build --no-cache && docker compose up -d

test:
	bash scripts/test.sh 127.0.0.1

bench:
	@echo "需要 dnsperf: apt install dnsperf"
	dnsperf -s 127.0.0.1 -d scripts/querylist.txt -c 100 -l 15

clean:
	docker compose down
	rm -rf cache/

pull-rules:
	cd rules/dat && \
	curl -LJO https://github.com/Loyalsoldier/v2ray-rules-dat/releases/latest/download/geoip.dat && \
	curl -LJO https://github.com/Loyalsoldier/v2ray-rules-dat/releases/latest/download/geosite.dat && \
	./v2dat unpack geoip  -o . -f private geoip.dat && \
	./v2dat unpack geoip  -o . -f cn geoip.dat && \
	./v2dat unpack geosite -o . -f cn geosite.dat && \
	./v2dat unpack geosite -o . -f gfw geosite.dat && \
	./v2dat unpack geosite -o . -f category-ads-all geosite.dat && \
	./v2dat unpack geosite -o . -f geolocation-!cn geosite.dat
