# GoDaddy DNS CLI

A simple command-line tool for managing GoDaddy DNS records.

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

Add to your shell config:

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

# Add/update a CNAME record
godaddy cname example.com app cname.vercel-dns.com

# Add/update an A record
godaddy a example.com @ 76.76.21.21

# Add any record type
godaddy add example.com TXT _verification "verify=abc123"

# Delete a record
godaddy delete example.com CNAME app

# Get a specific record
godaddy get example.com A @
```

## License

MIT
