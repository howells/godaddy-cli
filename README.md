# GoDaddy DNS CLI

A command-line tool for managing GoDaddy DNS records. Supports both human and agent workflows with structured JSON output, input validation, and safety rails.

## Installation

### Homebrew (macOS)

```bash
brew install howells/tap/godaddy
```

### Manual

```bash
curl -fsSL https://raw.githubusercontent.com/howells/godaddy-cli/main/godaddy -o /usr/local/bin/godaddy
chmod +x /usr/local/bin/godaddy
```

## Setup

Get your API credentials at [developer.godaddy.com/keys](https://developer.godaddy.com/keys)

```bash
# bash/zsh
export GODADDY_KEY='your-key'
export GODADDY_SECRET='your-secret'

# fish
set -gx GODADDY_KEY 'your-key'
set -gx GODADDY_SECRET 'your-secret'
```

## Usage

```bash
# List all DNS records
godaddy list example.com

# List with field filtering
godaddy list example.com --fields name,type,data

# Add/update records
godaddy cname example.com app cname.vercel-dns.com
godaddy a example.com @ 76.76.21.21
godaddy add example.com TXT _verification "verify=abc123"

# Preview before mutating
godaddy add example.com A @ 1.2.3.4 --dry-run

# Delete a record (requires confirmation)
godaddy delete example.com CNAME app
godaddy delete example.com CNAME app --yes  # skip prompt

# Get a specific record
godaddy get example.com A @

# List domains
godaddy domains

# CLI schema (for agents/tooling)
godaddy schema
```

## Agent / Automation Support

The CLI auto-detects piped contexts and switches to structured JSON output:

```bash
# Piped output is JSON by default
godaddy list example.com | jq '.[] | .name'

# Explicit output format
godaddy list example.com --output json

# Raw JSON input for mutations
godaddy add example.com --json '[{"type":"A","name":"@","data":"1.2.3.4","ttl":600}]'

# From stdin
echo '[{"type":"A","name":"@","data":"1.2.3.4","ttl":600}]' | godaddy add example.com --json -

# Full CLI schema for runtime introspection
godaddy schema
```

See [AGENTS.md](AGENTS.md) for detailed agent integration guidance.

## License

MIT
