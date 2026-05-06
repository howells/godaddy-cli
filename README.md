# GoDaddy DNS CLI

A small, scriptable command-line tool for managing GoDaddy DNS records.

It is built for both humans and automation: text output in an interactive
terminal, JSON output when piped, a runtime schema for agents, dry-run support
for mutations, and strict input validation around URL-sensitive arguments.

Current CLI version: `2.0.0`

## Contents

- [Install](#install)
- [Setup](#setup)
- [Quick start](#quick-start)
- [Command reference](#command-reference)
- [Global options](#global-options)
- [Common workflows](#common-workflows)
- [JSON and automation](#json-and-automation)
- [Safety and validation](#safety-and-validation)
- [Troubleshooting](#troubleshooting)
- [Development](#development)

## Install

### Homebrew

```bash
brew install howells/tap/godaddy
```

### Manual

```bash
curl -fsSL https://raw.githubusercontent.com/howells/godaddy-cli/main/godaddy \
  -o /usr/local/bin/godaddy
chmod +x /usr/local/bin/godaddy
```

### Requirements

- Bash
- `curl`
- `jq`

On macOS:

```bash
brew install jq
```

On Debian or Ubuntu:

```bash
sudo apt-get update
sudo apt-get install -y jq curl
```

Verify the install:

```bash
godaddy --version
godaddy --help
```

## Setup

Create GoDaddy API credentials at
[developer.godaddy.com/keys](https://developer.godaddy.com/keys).

Then export them in your shell:

```bash
# bash/zsh
export GODADDY_KEY='your-key'
export GODADDY_SECRET='your-secret'
```

```fish
# fish
set -gx GODADDY_KEY 'your-key'
set -gx GODADDY_SECRET 'your-secret'
```

Commands that call the GoDaddy API require both variables. `--help`,
`--version`, `schema`, and `--dry-run` mutation previews do not need live
credentials.

## Quick start

List records:

```bash
godaddy list example.com
```

List only the fields you need:

```bash
godaddy list example.com --fields name,type,data,ttl
```

Preview a record change before touching DNS:

```bash
godaddy add example.com A @ 1.2.3.4 --dry-run
```

Apply the change:

```bash
godaddy add example.com A @ 1.2.3.4
```

Delete safely:

```bash
godaddy get example.com CNAME app --output json
godaddy delete example.com CNAME app --dry-run --output json
godaddy delete example.com CNAME app --yes --output json
```

Ask the CLI to describe itself:

```bash
godaddy schema
```

## Command reference

```bash
godaddy [options] <command> [args]
```

Global options can appear before or after the command.

| Command | Description |
| --- | --- |
| `godaddy list <domain> [type]` | List DNS records for a domain, optionally filtered by record type. |
| `godaddy get <domain> <type> <name>` | Get one DNS record by type and name. |
| `godaddy add <domain> <type> <name> <data> [ttl]` | Add or update a DNS record. Default TTL is `600`. |
| `godaddy delete <domain> <type> <name>` | Delete a DNS record. Requires confirmation or `--yes`. |
| `godaddy cname <domain> <name> <target>` | Shortcut for adding a `CNAME` record. |
| `godaddy a <domain> <name> <ip>` | Shortcut for adding an `A` record. |
| `godaddy domains` | List all domains in the GoDaddy account. |
| `godaddy schema` | Output the complete CLI schema as JSON. |

Supported record types:

```text
A AAAA CNAME MX NS SOA SRV TXT CAA
```

Record types are case-sensitive. For example, use `CNAME`, not `cname`.

## Global options

| Option | Description |
| --- | --- |
| `--output json\|text` | Force JSON or human-readable text. Defaults to text in a TTY and JSON when stdout is piped. |
| `--dry-run` | Preview a mutation without calling the GoDaddy API. Supported by `add`, `delete`, `cname`, and `a`. |
| `--yes`, `-y` | Skip delete confirmation. Required for `delete` in non-interactive contexts. |
| `--fields f1,f2` | Return only selected fields from JSON arrays or objects. Useful for large DNS zones and agent context control. |
| `--limit N` | Limit array results to the first `N` items. `0` returns an empty array. |
| `--json <payload>` | Pass a raw JSON payload to `add`. Use `--json -` to read from stdin. |
| `-v`, `--version` | Show the CLI version. |
| `-h`, `--help` | Show text help in a TTY, or JSON schema when piped. |

Equals syntax is also supported for value options:

```bash
godaddy list example.com --output=json --fields=name,type --limit=25
```

## Common workflows

### Inspect a zone

```bash
godaddy list example.com --fields name,type,data,ttl --limit 100 --output json
```

Filter by type:

```bash
godaddy list example.com TXT --fields name,data --output json
```

Get a single record:

```bash
godaddy get example.com A @ --output json
```

### Add an A record

```bash
godaddy list example.com A --fields name,data,ttl --output json
godaddy add example.com A @ 76.76.21.21 --dry-run --output json
godaddy add example.com A @ 76.76.21.21 --output json
```

The `a` shortcut does the same thing:

```bash
godaddy a example.com @ 76.76.21.21 --dry-run --output json
godaddy a example.com @ 76.76.21.21 --output json
```

### Add a CNAME record

```bash
godaddy cname example.com app cname.vercel-dns.com --dry-run --output json
godaddy cname example.com app cname.vercel-dns.com --output json
```

### Add a TXT record

```bash
godaddy add example.com TXT _verification "verify=abc123" --dry-run --output json
godaddy add example.com TXT _verification "verify=abc123" --output json
```

### Set a custom TTL

```bash
godaddy add example.com A api 1.2.3.4 3600 --dry-run --output json
godaddy add example.com A api 1.2.3.4 3600 --output json
```

### Delete a record

Use `get` first so you know exactly what will be deleted:

```bash
godaddy get example.com CNAME app --output json
godaddy delete example.com CNAME app --dry-run --output json
godaddy delete example.com CNAME app --yes --output json
```

In an interactive text terminal, `delete` prompts for confirmation if `--yes`
is omitted. In JSON, piped, or non-interactive contexts, `--yes` is required.

### Add multiple records with raw JSON

`--json` sends the payload directly to the GoDaddy records API shape. This is
useful for record types with extra fields or for multi-record updates.

```bash
godaddy add example.com --json '[
  {"type":"A","name":"@","data":"1.1.1.1","ttl":300},
  {"type":"A","name":"@","data":"2.2.2.2","ttl":300}
]' --dry-run --output json
```

From stdin:

```bash
echo '[{"type":"MX","name":"@","data":"mail.example.com","ttl":3600}]' \
  | godaddy add example.com --json - --dry-run --output json
```

## JSON and automation

The CLI auto-detects output mode:

- TTY stdout: text
- Piped stdout: JSON
- Explicit override: `--output json` or `--output text`

Examples:

```bash
godaddy list example.com | jq '.[] | {name,type,data}'
godaddy list example.com --output json
godaddy list example.com --output text
```

### Runtime schema

`godaddy schema` returns machine-readable metadata for commands, arguments,
global options, record types, authentication, and input validation.

```bash
godaddy schema | jq '.commands | keys'
godaddy schema | jq '.global_options'
```

`godaddy --help` also returns the schema when stdout is piped:

```bash
godaddy --help | jq '.commands.add'
```

### Response shapes

Successful `add` in JSON mode:

```json
{
  "ok": true,
  "message": "Added A @ → 1.2.3.4 to example.com",
  "data": [
    {
      "type": "A",
      "name": "@",
      "data": "1.2.3.4",
      "ttl": 600
    }
  ]
}
```

Successful `delete` in JSON mode:

```json
{
  "ok": true,
  "message": "Deleted CNAME record: app.example.com"
}
```

Validation or API error in JSON mode:

```json
{
  "ok": false,
  "error": "Destructive operation requires --yes flag (or use --dry-run to preview)",
  "code": 1
}
```

Dry-run `add`:

```json
{
  "dry_run": true,
  "domain": "example.com",
  "method": "PATCH",
  "payload": [
    {
      "type": "A",
      "name": "@",
      "data": "1.2.3.4",
      "ttl": 600
    }
  ]
}
```

Dry-run `delete`:

```json
{
  "dry_run": true,
  "domain": "example.com",
  "method": "DELETE",
  "type": "CNAME",
  "name": "app"
}
```

## Safety and validation

DNS mutations are intentionally explicit:

- Use `--dry-run` before `add`, `delete`, `cname`, or `a`.
- Use `--yes` for `delete` in non-interactive contexts.
- Use `--fields` and `--limit` when listing large zones.
- Prefer `--output json` for scripts and agents.

The CLI rejects unsafe input in `domain`, `type`, and `name` arguments:

| Pattern | Example | Why it is rejected |
| --- | --- | --- |
| Path traversal | `../` | Prevents URL path manipulation. |
| Query or fragment characters | `?key=value`, `#frag` | Prevents query or fragment injection. |
| Control characters | newline, NUL | Prevents protocol injection. |
| Percent encoding | `%2e`, `%2F` | Prevents bypassing the checks above. |

`add` also validates positional record types and TTL values. Raw `--json`
payloads are checked for valid JSON syntax and then passed through as payloads,
so preview them with `--dry-run` before applying.

## Troubleshooting

### `jq is required`

Install `jq`:

```bash
brew install jq
```

or:

```bash
sudo apt-get install -y jq
```

### `GODADDY_KEY and GODADDY_SECRET environment variables required`

The command needs live GoDaddy API access. Export both variables:

```bash
export GODADDY_KEY='your-key'
export GODADDY_SECRET='your-secret'
```

### `Destructive operation requires --yes flag`

You are deleting in a non-interactive context. Preview first, then pass `--yes`:

```bash
godaddy delete example.com CNAME app --dry-run --output json
godaddy delete example.com CNAME app --yes --output json
```

### `Invalid record type`

Use one of:

```text
A AAAA CNAME MX NS SOA SRV TXT CAA
```

Record types are uppercase.

### `TTL must be a positive integer`

Pass a numeric TTL:

```bash
godaddy add example.com A @ 1.2.3.4 600
```

## Agent guide

For agent-specific operating rules, including dry-run discipline, context
control, response envelopes, and schema introspection, see [AGENTS.md](AGENTS.md).

## Development

Run the test suite:

```bash
./test.sh
```

The suite covers version/help behavior, schema introspection, input
sanitization, validation, dry runs, safety rails, raw JSON input, field
filtering, limits, record types, output envelopes, flag parsing, and credential
handling.

Before changing command behavior, update the script, the tests, `AGENTS.md`,
and this README together so the human docs, agent docs, and runtime schema stay
in sync.

## License

MIT
