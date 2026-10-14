# Check model

The dashboard is an evidence-oriented checklist, not an account-risk score. Its statuses mean:

| Status | Meaning |
| --- | --- |
| `pass` | Observed value matched an explicit safe condition or user expectation. |
| `review` | Evidence exists, but human intent or context is required. |
| `risk` | Observed value conflicts with an explicit expectation or exposes a concrete configuration concern. |
| `unknown` | The collector cannot safely or reliably test this item. |
| `info` | A value was inventoried, but it is not itself a pass/fail safety condition. |
| `na` | The feature is not present or does not apply to the detected environment. |

`automated=false` means the local collector deliberately did not test the item. The dashboard may provide a reversible checkbox so the user can record a completed human review. Such a result is labelled `人工确认`, stored only in the local `state` directory, and must never be presented as an automatic test.

## Coverage

- **Account and payment:** locally unverifiable. Do not log in, scrape account pages, or copy sensitive values merely to satisfy the checker.
- **Language and timezone:** inventory automatically; compare only when the user supplies expectations.
- **Device and Firefox isolation:** detect profiles and the default-browser handler. A profile name is only a hint; it does not prove exclusive use.
- **Network:** inventory routes, DNS, Windows/PAC/WinHTTP/environment proxies, the proxy configured in ClaudeSafe, its matching local listener, relevant processes, and outbound firewall rules. Automatic checks stay offline. A listener proves only that a local proxy process is running; it does not prove the public exit or tunnel health.
- **Disconnect protection:** manual by default. Do not automate disconnects or firewall changes as part of an audit.
- **WebRTC and location:** inspect Firefox preference files and Windows location consent. Site-specific Firefox permissions remain manual when they cannot be read reliably.
- **Claude Code:** summarize permission configuration and recent tool names/counts without copying prompts, command arguments, file contents, or tool results.
- **Third-party connectors:** locally unverifiable unless the relevant service provides a trustworthy local permission inventory. Do not send connector contents to the model for checking.

## Overall status

`risk` wins over `review`, which wins over `unknown`, which wins over `pass`. `info` and `na` do not improve the overall result. The overall value is a triage signal, not a probability and not a guarantee.

The report also exposes a practical `readiness` value. `hold` means at least one local `risk` or `review` item should be handled before opening Claude. `proceed-with-limits` means no local blocker was detected, while manual and external checks may still remain. It is not an account-safety guarantee.

For category cards, any unconfirmed manual or unknown item prevents an all-clear label. Use “still needs verification” rather than “no action needed.” Keep raw process IDs and long rule listings in technical evidence; the overview should show compact counts.

## Floating lights

The compact always-on-top window maps each category to one lamp:

- Green: at least one explicit automatic `pass` or a recorded `人工确认`, with no remaining `risk`, `review`, `unknown`, or unconfirmed manual item in that category.
- Red: at least one `risk` or `review` item.
- Gray: any unknown or unconfirmed manual item, an informational-only category, or a category that is not applicable.

Green means “supported by an automatic check or an explicitly labelled human confirmation,” not a guarantee of account safety. Clicking a lamp opens the complete dashboard; item evidence remains in the detail view.

## Safe remediation boundary

The collector is read-only. Recommended changes can affect connectivity or access. Before applying any change, identify the exact setting, explain impact and rollback, obtain authorization, and verify the result. Never change billing identity or location data to create artificial consistency.

