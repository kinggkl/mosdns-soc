// SPDX-License-Identifier: GPL-3.0-or-later
package sequence

import (
	"context"
	"testing"

	"github.com/IrineSistiana/mosdns/v5/pkg/query_context"
	"github.com/miekg/dns"
)

func TestIPv4OnlyAnswersLocally(t *testing.T) {
	for qtype, status := range map[uint16]int{dns.TypeAAAA: dns.RcodeSuccess, dns.TypeSVCB: dns.RcodeSuccess, dns.TypeHTTPS: dns.RcodeNameError} {
		query := new(dns.Msg).SetQuestion("example.test.", qtype)
		qCtx := query_context.NewContext(query)
		next := NewChainWalker([]*ChainNode{{E: ExecutableFunc(func(context.Context, *query_context.Context) error {
			t.Fatal("blocked query reached the upstream sequence")
			return nil
		})}}, nil)
		if err := ipv4Only(context.Background(), qCtx, next); err != nil {
			t.Fatal(err)
		}
		if r := qCtx.R(); r == nil || r.Rcode != status || len(r.Answer) != 0 {
			t.Fatalf("qtype %d: expected empty response with rcode %d, got %v", qtype, status, r)
		}
	}
}

func TestIPv4OnlyFiltersAllSections(t *testing.T) {
	for _, qtype := range []uint16{dns.TypeA, dns.TypeANY} {
		query := new(dns.Msg).SetQuestion("example.test.", qtype)
		qCtx := query_context.NewContext(query)
		a, _ := dns.NewRR("example.test. 60 IN A 192.0.2.1")
		aaaa, _ := dns.NewRR("example.test. 60 IN AAAA 2001:db8::1")
		https, err := dns.NewRR("example.test. 60 IN HTTPS 1 . ipv6hint=2001:db8::1")
		if err != nil {
			t.Fatal(err)
		}
		original := new(dns.Msg).SetReply(query)
		original.AuthenticatedData = true
		original.Answer = []dns.RR{a, aaaa}
		original.Ns = []dns.RR{aaaa}
		original.Extra = []dns.RR{https, aaaa}
		next := NewChainWalker([]*ChainNode{{E: ExecutableFunc(func(_ context.Context, qCtx *query_context.Context) error {
			qCtx.SetResponse(original)
			return nil
		})}}, nil)
		if err := ipv4Only(context.Background(), qCtx, next); err != nil {
			t.Fatal(err)
		}
		r := qCtx.R()
		if r.AuthenticatedData || len(r.Answer) != 1 || r.Answer[0].Header().Rrtype != dns.TypeA || len(r.Ns) != 0 || len(r.Extra) != 0 {
			t.Fatalf("qtype %d: expected only A record, got %v", qtype, r)
		}
		if len(original.Answer) != 2 || len(original.Extra) != 2 {
			t.Fatal("filter mutated the original response")
		}
	}
}
