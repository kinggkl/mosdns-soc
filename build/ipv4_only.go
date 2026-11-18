// SPDX-License-Identifier: GPL-3.0-or-later
package sequence

import (
	"context"
	"fmt"
	"slices"

	"github.com/IrineSistiana/mosdns/v5/pkg/query_context"
	"github.com/miekg/dns"
)

func init() {
	MustRegExecQuickSetup("ipv4_only", func(_ BQ, args string) (any, error) {
		if args != "" {
			return nil, fmt.Errorf("ipv4_only takes no arguments")
		}
		return RecursiveExecutableFunc(ipv4Only), nil
	})
}

func ipv4Only(ctx context.Context, qCtx *query_context.Context, next ChainWalker) error {
	switch qCtx.QQuestion().Qtype {
	case dns.TypeAAAA, dns.TypeSVCB:
		qCtx.SetResponse(new(dns.Msg).SetReply(qCtx.Q()))
		return nil
	case dns.TypeHTTPS:
		// Keep the existing HTTPS query policy.
		qCtx.SetResponse(new(dns.Msg).SetRcode(qCtx.Q(), dns.RcodeNameError))
		return nil
	}

	if err := next.ExecNext(ctx, qCtx); err != nil {
		return err
	}

	response := qCtx.R()
	if response == nil {
		return nil
	}
	answer, authority, additional := stripIPv6(response.Answer), stripIPv6(response.Ns), stripIPv6(response.Extra)
	if len(answer) != len(response.Answer) || len(authority) != len(response.Ns) || len(additional) != len(response.Extra) {
		filtered := *response
		filtered.Answer, filtered.Ns, filtered.Extra = answer, authority, additional
		filtered.AuthenticatedData = false
		qCtx.SetResponse(&filtered)
	}
	return nil
}

func stripIPv6(records []dns.RR) []dns.RR {
	first := slices.IndexFunc(records, suppressedRecord)
	if first < 0 {
		return records
	}
	return slices.DeleteFunc(slices.Clone(records), suppressedRecord)
}

func suppressedRecord(record dns.RR) bool {
	recordType := record.Header().Rrtype
	if signature, ok := record.(*dns.RRSIG); ok {
		recordType = signature.TypeCovered
	}
	return recordType == dns.TypeAAAA || recordType == dns.TypeSVCB || recordType == dns.TypeHTTPS
}
