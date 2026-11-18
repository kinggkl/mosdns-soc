.PHONY: deploy update-rules test bench clean

deploy:
	sh scripts/deploy.sh

update-rules:
	sh rules/update.sh

test:
	sh scripts/test.sh 127.0.0.1 "$${DNS_PORT:-53}"

bench:
	@echo "需要 dnsperf: apt install dnsperf"
	dnsperf -s 127.0.0.1 -d scripts/querylist.txt -c 100 -l 15

clean:
	docker compose down
	rm -rf cache/
