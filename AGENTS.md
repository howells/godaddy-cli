---
name: godaddy-dns-cli
version: 2.0.0
surface: cli
---

# GoDaddy DNS CLI — Agent Guide

## Defaults

- **Output auto-detection**: stdout is JSON when piped, text when TTY
- **Force format**: `--output json` or `--output text`
- **Runtime schema**: `godaddy schema` returns full CLI schema as JSON
- **Help as schema**: `godaddy --help` outputs JSON schema when piped

## Guardrails

- **Always use `--dry-run`** before mutations (`add`, `delete`, `cname`, `a`)
- **Always use `--fields`** to select only needed fields — protects context window
- **Always use `--yes`** for `delete` in non-interactive contexts (required, not optional)
- **Use `--limit N`** when listing records for domains with many entries

## Workflows

### Add a DNS record

```bash
# 1. Check existing records
godaddy list example.com --fields name,type,data --output json

# 2. Preview the mutation
godaddy add example.com A @ 1.2.3.4 --dry-run --output json

# 3. Execute
godaddy add example.com A @ 1.2.3.4 --output json
```

### Delete a DNS record

```bash
# 1. Verify the record exists
godaddy get example.com CNAME app --output json

# 2. Preview the deletion
godaddy delete example.com CNAME app --dry-run --output json

# 3. Execute (--yes is required in non-interactive contexts)
godaddy delete example.com CNAME app --yes --output json
```

### Raw JSON payload

```bash
# Direct payload — bypasses positional args, maps to API schema
godaddy add example.com --json '[{"type":"A","name":"@","data":"1.2.3.4","ttl":600}]' --output json

# From stdin
echo '[{"type":"MX","name":"@","data":"mail.example.com","ttl":3600}]' \
  | godaddy add example.com --json - --output json
```

### Introspection

```bash
# Full CLI schema with all commands, args, types, and enums
godaddy schema

# Also available via help when piped
godaddy --help | jq '.commands | keys'
```

## Input Validation

The CLI rejects the following in domain, type, and name arguments:

| Pattern | Example | Reason |
|---------|---------|--------|
| Path traversal | `../` | URL path manipulation |
| Query/fragment | `?key=val`, `#frag` | Query parameter injection |
| Control characters | `\x00`, `\n` | Protocol injection |
| Percent-encoding | `%2e`, `%2F` | Bypass of above checks |

## Valid Record Types

`A`, `AAAA`, `CNAME`, `MX`, `NS`, `SOA`, `SRV`, `TXT`, `CAA`

## Authentication

Set `GODADDY_KEY` and `GODADDY_SECRET` environment variables.
Obtain at: https://developer.godaddy.com/keys

## Response Envelope

All mutations return a consistent envelope in JSON mode:

```json
// Success
{"ok": true, "message": "Added A @ → 1.2.3.4 to example.com", "data": [...]}

// Error
{"ok": false, "error": "Not Found (HTTP 404)", "code": 404}

// Dry run
{"dry_run": true, "domain": "example.com", "method": "PATCH", "payload": [...]}
```
