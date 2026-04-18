#!/bin/bash
# Test suite for godaddy CLI
# Run: ./test.sh

DIR="$(cd "$(dirname "$0")" && pwd)"
CLI="$DIR/godaddy"

PASS=0 FAIL=0 TOTAL=0

# ── Helpers ───────────────────────────────────────────────────────
pass() { ((PASS++)); ((TOTAL++)); printf '  \033[32m✓\033[0m %s\n' "$1"; }
fail() { ((FAIL++)); ((TOTAL++)); printf '  \033[31m✗\033[0m %s\n' "$1"; }

assert_eq() {
    local desc="$1" expected="$2" actual="$3"
    if [[ "$expected" == "$actual" ]]; then
        pass "$desc"
    else
        fail "$desc"
        printf '    expected: %s\n    got:      %s\n' "$expected" "$actual"
    fi
}

assert_contains() {
    local desc="$1" needle="$2" haystack="$3"
    if [[ "$haystack" == *"$needle"* ]]; then
        pass "$desc"
    else
        fail "$desc"
        printf '    expected to contain: %s\n' "$needle"
    fi
}

assert_not_contains() {
    local desc="$1" needle="$2" haystack="$3"
    if [[ "$haystack" != *"$needle"* ]]; then
        pass "$desc"
    else
        fail "$desc"
        printf '    expected NOT to contain: %s\n' "$needle"
    fi
}

assert_exit() {
    local desc="$1" expected="$2"
    shift 2
    "$@" >/dev/null 2>&1
    local actual=$?
    assert_eq "$desc" "$expected" "$actual"
}

assert_json() {
    local desc="$1" json="$2" query="$3" expected="$4"
    local actual
    actual=$(echo "$json" | jq -r "$query" 2>/dev/null)
    assert_eq "$desc" "$expected" "$actual"
}

section() { printf '\n── %s ──\n' "$1"; }

# ══════════════════════════════════════════════════════════════════
# VERSION
# ══════════════════════════════════════════════════════════════════
section "Version"

out=$("$CLI" --version 2>&1)
assert_json "--version outputs JSON when piped" "$out" ".version" "2.0.0"

out=$("$CLI" -v 2>&1)
assert_json "-v alias outputs JSON when piped" "$out" ".version" "2.0.0"

out=$("$CLI" --output text --version 2>&1)
assert_eq "--output text --version gives text" "godaddy v2.0.0" "$out"

# ══════════════════════════════════════════════════════════════════
# HELP
# ══════════════════════════════════════════════════════════════════
section "Help"

out=$("$CLI" --help 2>&1)
assert_json "--help outputs schema when piped" "$out" ".name" "godaddy"

out=$("$CLI" -h 2>&1)
assert_json "-h alias works" "$out" ".name" "godaddy"

out=$("$CLI" --output text --help 2>&1)
assert_contains "text help has Commands" "Commands:" "$out"
assert_contains "text help has Global Options" "Global Options:" "$out"
assert_contains "text help has Examples" "Examples:" "$out"
assert_contains "text help has --dry-run" "--dry-run" "$out"
assert_contains "text help has --fields" "--fields" "$out"
assert_contains "text help has --json" "--json" "$out"
assert_contains "text help has schema command" "schema" "$out"

out=$("$CLI" 2>&1)
assert_json "no args shows help (schema when piped)" "$out" ".name" "godaddy"

# ══════════════════════════════════════════════════════════════════
# SCHEMA INTROSPECTION
# ══════════════════════════════════════════════════════════════════
section "Schema Introspection"

schema=$("$CLI" schema 2>&1)

# Valid JSON
echo "$schema" | jq empty 2>/dev/null && pass "schema is valid JSON" || fail "schema is not valid JSON"

assert_json "schema has name" "$schema" ".name" "godaddy"
assert_json "schema has version" "$schema" ".version" "2.0.0"
assert_json "schema has description" "$schema" ".description" "GoDaddy DNS management CLI"

# All commands present
for cmd in list get add delete cname a domains schema; do
    val=$(echo "$schema" | jq -r ".commands.\"$cmd\".description // empty")
    [[ -n "$val" ]] && pass "schema has '$cmd' command" || fail "schema missing '$cmd' command"
done

# All global options present
for opt in "--output" "--dry-run" "--yes" "--fields" "--limit" "--json"; do
    val=$(echo "$schema" | jq -r ".global_options.\"$opt\".description // empty")
    [[ -n "$val" ]] && pass "schema has '$opt' option" || fail "schema missing '$opt' option"
done

# Mutation metadata
assert_json "add is mutating" "$schema" ".commands.add.mutating" "true"
assert_json "list is not mutating" "$schema" ".commands.list.mutating" "false"
assert_json "delete supports dry-run" "$schema" ".commands.delete.supports_dry_run" "true"
assert_json "delete requires confirmation" "$schema" ".commands.delete.requires_confirmation" "true"
assert_json "delete confirmation skip" "$schema" ".commands.delete.confirmation_skip" "--yes"
assert_json "add supports JSON input" "$schema" ".commands.add.supports_json_input" "true"

# Auth
assert_json "auth method" "$schema" ".auth.method" "environment_variables"
assert_json "auth requires GODADDY_KEY" "$schema" ".auth.required[0]" "GODADDY_KEY"
assert_json "auth requires GODADDY_SECRET" "$schema" ".auth.required[1]" "GODADDY_SECRET"

# Security posture
assert_json "security posture declared" "$schema" ".input_validation.security_posture" "The agent is not a trusted operator"

# Record types enum
count=$(echo "$schema" | jq '.record_types | length')
assert_eq "schema has 9 record types" "9" "$count"

# Args have types and required flags
assert_json "list domain is required" "$schema" ".commands.list.args[0].required" "true"
assert_json "list type is optional" "$schema" ".commands.list.args[1].required" "false"
assert_json "add ttl has default" "$schema" ".commands.add.args[4].default" "600"

# ══════════════════════════════════════════════════════════════════
# INPUT SANITIZATION
# ══════════════════════════════════════════════════════════════════
section "Input Sanitization"

# Path traversal
out=$("$CLI" --output json list "../etc" 2>&1)
assert_json "rejects .. in domain" "$out" ".error" "domain: path traversal (..) rejected"
assert_exit ".. exits 1" 1 "$CLI" --output json list "../etc"

out=$("$CLI" --output json list "foo/../bar" 2>&1)
assert_json "rejects embedded .." "$out" ".error" "domain: path traversal (..) rejected"

# Query character
out=$("$CLI" --output json list "example.com?x=1" 2>&1)
assert_json "rejects ? in domain" "$out" ".error" "domain: query/fragment character rejected"

# Fragment character
out=$("$CLI" --output json list "example.com#frag" 2>&1)
assert_json "rejects # in domain" "$out" ".error" "domain: query/fragment character rejected"

# Percent-encoding
out=$("$CLI" --output json list "example%2ecom" 2>&1)
assert_json "rejects %XX in domain" "$out" ".error" "domain: percent-encoding rejected"

out=$("$CLI" --output json list "%2F%2F" 2>&1)
assert_json "rejects %2F" "$out" ".error" "domain: percent-encoding rejected"

# Sanitization on type argument
out=$("$CLI" --output json get example.com "..%2f" name 2>&1)
assert_json "rejects .. in type" "$out" ".error" "type: path traversal (..) rejected"

# Sanitization on name argument
out=$("$CLI" --output json get example.com A "?inject" 2>&1)
assert_json "rejects ? in name" "$out" ".error" "name: query/fragment character rejected"

# Valid inputs pass sanitization (will fail at creds, not sanitization)
out=$("$CLI" --output json list "example.com" 2>&1)
assert_not_contains "valid domain passes sanitization" "rejected" "$out"

out=$("$CLI" --output json --dry-run add "my-domain.co.uk" A @ 1.2.3.4 2>&1)
assert_json "hyphenated domain passes" "$out" ".domain" "my-domain.co.uk"

out=$("$CLI" --output json --dry-run add "example.com" A "_dmarc" test 2>&1)
assert_json "underscore name passes" "$out" ".payload[0].name" "_dmarc"

# ══════════════════════════════════════════════════════════════════
# VALIDATION
# ══════════════════════════════════════════════════════════════════
section "Validation"

# Invalid record type
out=$("$CLI" --output json --dry-run add example.com INVALID @ test 2>&1)
assert_contains "rejects invalid record type" "Invalid record type" "$out"
assert_exit "invalid type exits 1" 1 "$CLI" --output json --dry-run add example.com INVALID @ test

# Case-sensitive type (lowercase rejected)
out=$("$CLI" --output json --dry-run add example.com cname @ test 2>&1)
assert_contains "rejects lowercase type" "Invalid record type" "$out"

# Invalid TTL
out=$("$CLI" --output json --dry-run add example.com A @ 1.2.3.4 abc 2>&1)
assert_contains "rejects non-numeric TTL" "TTL must be a positive integer" "$out"
assert_exit "invalid TTL exits 1" 1 "$CLI" --output json --dry-run add example.com A @ 1.2.3.4 abc

out=$("$CLI" --output json --dry-run add example.com A @ 1.2.3.4 -5 2>&1)
assert_contains "rejects negative TTL" "TTL must be a positive integer" "$out"

# Missing required args
assert_exit "list requires domain" 1 "$CLI" --output json list
assert_exit "get requires 3 args (1 given)" 1 "$CLI" --output json get example.com
assert_exit "get requires 3 args (2 given)" 1 "$CLI" --output json get example.com A
assert_exit "add requires domain" 1 "$CLI" --output json --dry-run add
assert_exit "add requires 4 args (2 given)" 1 "$CLI" --output json --dry-run add example.com A
assert_exit "delete requires 3 args" 1 "$CLI" --output json delete example.com A
assert_exit "cname requires 3 args" 1 "$CLI" --output json --dry-run cname example.com
assert_exit "a requires 3 args" 1 "$CLI" --output json --dry-run a example.com

# Unknown command
out=$("$CLI" --output json foobar 2>&1)
assert_contains "unknown command reports name" "Unknown command 'foobar'" "$out"
assert_exit "unknown command exits 1" 1 "$CLI" --output json foobar

# Invalid --limit
out=$("$CLI" --output json --limit abc list example.com 2>&1)
assert_contains "rejects non-numeric limit" "--limit must be a positive integer" "$out"
assert_exit "invalid limit exits 1" 1 "$CLI" --output json --limit abc list example.com

# ══════════════════════════════════════════════════════════════════
# DRY RUN
# ══════════════════════════════════════════════════════════════════
section "Dry Run"

# Add dry-run (no credentials needed)
out=$("$CLI" --output json --dry-run add example.com A @ 1.2.3.4 2>&1)
assert_json "add dry-run: dry_run=true" "$out" ".dry_run" "true"
assert_json "add dry-run: domain" "$out" ".domain" "example.com"
assert_json "add dry-run: method=PATCH" "$out" ".method" "PATCH"
assert_json "add dry-run: payload type" "$out" ".payload[0].type" "A"
assert_json "add dry-run: payload name" "$out" ".payload[0].name" "@"
assert_json "add dry-run: payload data" "$out" ".payload[0].data" "1.2.3.4"
assert_json "add dry-run: default ttl=600" "$out" ".payload[0].ttl" "600"
assert_exit "add dry-run exits 0" 0 "$CLI" --output json --dry-run add example.com A @ 1.2.3.4

# Custom TTL
out=$("$CLI" --output json --dry-run add example.com A @ 1.2.3.4 3600 2>&1)
assert_json "add dry-run: custom ttl=3600" "$out" ".payload[0].ttl" "3600"

# Delete dry-run
out=$("$CLI" --output json --dry-run delete example.com CNAME app 2>&1)
assert_json "delete dry-run: dry_run=true" "$out" ".dry_run" "true"
assert_json "delete dry-run: domain" "$out" ".domain" "example.com"
assert_json "delete dry-run: method=DELETE" "$out" ".method" "DELETE"
assert_json "delete dry-run: type" "$out" ".type" "CNAME"
assert_json "delete dry-run: name" "$out" ".name" "app"
assert_exit "delete dry-run exits 0" 0 "$CLI" --output json --dry-run delete example.com CNAME app

# CNAME shortcut dry-run
out=$("$CLI" --output json --dry-run cname example.com app cname.vercel-dns.com 2>&1)
assert_json "cname dry-run: type=CNAME" "$out" ".payload[0].type" "CNAME"
assert_json "cname dry-run: name" "$out" ".payload[0].name" "app"
assert_json "cname dry-run: target" "$out" ".payload[0].data" "cname.vercel-dns.com"
assert_exit "cname dry-run exits 0" 0 "$CLI" --output json --dry-run cname example.com app target

# A shortcut dry-run
out=$("$CLI" --output json --dry-run a example.com @ 76.76.21.21 2>&1)
assert_json "a dry-run: type=A" "$out" ".payload[0].type" "A"
assert_json "a dry-run: ip" "$out" ".payload[0].data" "76.76.21.21"
assert_exit "a dry-run exits 0" 0 "$CLI" --output json --dry-run a example.com @ 1.1.1.1

# Text-mode dry-run
out=$("$CLI" --output text --dry-run add example.com A @ 1.2.3.4 2>&1)
assert_contains "text dry-run has [dry-run]" "[dry-run]" "$out"
assert_contains "text dry-run has domain" "example.com" "$out"

out=$("$CLI" --output text --dry-run delete example.com TXT _verify 2>&1)
assert_contains "text delete dry-run has [dry-run]" "[dry-run]" "$out"
assert_contains "text delete dry-run has type" "TXT" "$out"

# Dry-run does NOT require credentials
(unset GODADDY_KEY GODADDY_SECRET; "$CLI" --output json --dry-run add example.com A @ 1.2.3.4 >/dev/null 2>&1)
assert_eq "dry-run works without credentials" "0" "$?"

# ══════════════════════════════════════════════════════════════════
# SAFETY RAILS
# ══════════════════════════════════════════════════════════════════
section "Safety Rails"

# Delete without --yes in non-interactive (piped) context
out=$("$CLI" --output json delete example.com CNAME app 2>&1)
assert_contains "delete requires --yes" "requires --yes flag" "$out"
assert_contains "delete error mentions --dry-run" "--dry-run" "$out"
assert_exit "delete without --yes exits 1" 1 "$CLI" --output json delete example.com CNAME app

# Delete with --yes but no creds (gets past safety, fails at API)
out=$("$CLI" --output json --yes delete example.com CNAME app 2>&1)
assert_not_contains "--yes bypasses confirmation" "requires --yes" "$out"

# ══════════════════════════════════════════════════════════════════
# RAW JSON INPUT
# ══════════════════════════════════════════════════════════════════
section "Raw JSON Input"

# --json flag with dry-run
out=$("$CLI" --output json --dry-run add example.com \
    --json '[{"type":"MX","name":"@","data":"mail.example.com","ttl":3600}]' 2>&1)
assert_json "raw JSON: type preserved" "$out" ".payload[0].type" "MX"
assert_json "raw JSON: data preserved" "$out" ".payload[0].data" "mail.example.com"
assert_json "raw JSON: ttl preserved" "$out" ".payload[0].ttl" "3600"

# --json= equals syntax
out=$("$CLI" --output json --dry-run add example.com \
    --json='[{"type":"A","name":"@","data":"1.1.1.1","ttl":300}]' 2>&1)
assert_json "--json= syntax works" "$out" ".payload[0].data" "1.1.1.1"
assert_json "--json= ttl" "$out" ".payload[0].ttl" "300"

# stdin JSON (--json -)
out=$(echo '[{"type":"TXT","name":"_verify","data":"abc123","ttl":600}]' \
    | "$CLI" --output json --dry-run add example.com --json - 2>&1)
assert_json "stdin JSON: type" "$out" ".payload[0].type" "TXT"
assert_json "stdin JSON: data" "$out" ".payload[0].data" "abc123"

# Multiple records in one payload
out=$("$CLI" --output json --dry-run add example.com \
    --json '[{"type":"A","name":"@","data":"1.1.1.1","ttl":300},{"type":"A","name":"@","data":"2.2.2.2","ttl":300}]' 2>&1)
count=$(echo "$out" | jq '.payload | length')
assert_eq "multi-record payload preserved" "2" "$count"

# Invalid JSON rejected
out=$("$CLI" --output json --dry-run add example.com --json 'not-json' 2>&1)
assert_contains "rejects invalid JSON" "Invalid JSON payload" "$out"
assert_exit "invalid JSON exits 1" 1 "$CLI" --output json --dry-run add example.com --json 'not-json'

# Empty JSON array (valid JSON but unusual)
out=$("$CLI" --output json --dry-run add example.com --json '[]' 2>&1)
assert_json "empty array is valid JSON" "$out" ".dry_run" "true"

# JSON bypasses type/name/data requirement
out=$("$CLI" --output json --dry-run add example.com \
    --json '[{"type":"SRV","name":"_sip","data":"sip.example.com","ttl":600,"priority":10,"weight":5,"port":5060}]' 2>&1)
assert_json "JSON allows extra fields" "$out" ".payload[0].priority" "10"

# ══════════════════════════════════════════════════════════════════
# FIELD FILTERING (unit tests for _data jq logic)
# ══════════════════════════════════════════════════════════════════
section "Field Filtering"

jq_fields='($f|split(",")) as $k | if type=="array" then [.[]|with_entries(select(.key|IN($k[])))] else with_entries(select(.key|IN($k[]))) end'

# Single field from array
out=$(echo '[{"name":"@","type":"A","data":"1.2.3.4","ttl":600}]' \
    | jq -c --arg f "name" "$jq_fields")
assert_eq "single field from array" '[{"name":"@"}]' "$out"

# Multiple fields from array
out=$(echo '[{"name":"@","type":"A","data":"1.2.3.4","ttl":600}]' \
    | jq -c --arg f "name,type" "$jq_fields")
assert_eq "two fields from array" '[{"name":"@","type":"A"}]' "$out"

# Field filter on object
out=$(echo '{"name":"@","type":"A","data":"1.2.3.4","ttl":600}' \
    | jq -c --arg f "data" "$jq_fields")
assert_eq "field filter on object" '{"data":"1.2.3.4"}' "$out"

# Multiple items
out=$(echo '[{"a":1,"b":2,"c":3},{"a":4,"b":5,"c":6}]' \
    | jq -c --arg f "a,c" "$jq_fields")
assert_eq "fields across multiple items" '[{"a":1,"c":3},{"a":4,"c":6}]' "$out"

# Non-existent field returns empty objects
out=$(echo '[{"name":"@","type":"A"}]' \
    | jq -c --arg f "missing" "$jq_fields")
assert_eq "missing field returns empty" '[{}]' "$out"

# ══════════════════════════════════════════════════════════════════
# LIMIT (unit tests for _data jq logic)
# ══════════════════════════════════════════════════════════════════
section "Limit"

jq_limit='if type=="array" then .[:$n] else . end'

out=$(echo '[1,2,3,4,5]' | jq -c --argjson n 3 "$jq_limit")
assert_eq "limit=3 on 5 items" '[1,2,3]' "$out"

out=$(echo '[1,2,3]' | jq -c --argjson n 10 "$jq_limit")
assert_eq "limit > length is safe" '[1,2,3]' "$out"

out=$(echo '[1,2,3]' | jq -c --argjson n 1 "$jq_limit")
assert_eq "limit=1" '[1]' "$out"

out=$(echo '[1,2,3]' | jq -c --argjson n 0 "$jq_limit")
assert_eq "limit=0 returns empty" '[]' "$out"

out=$(echo '{"key":"val"}' | jq -c --argjson n 3 "$jq_limit")
assert_eq "limit on object is no-op" '{"key":"val"}' "$out"

# ══════════════════════════════════════════════════════════════════
# RECORD TYPES
# ══════════════════════════════════════════════════════════════════
section "Record Types"

for rtype in A AAAA CNAME MX NS SOA SRV TXT CAA; do
    assert_exit "$rtype is accepted" 0 \
        "$CLI" --output json --dry-run add example.com "$rtype" @ test
done

# ══════════════════════════════════════════════════════════════════
# OUTPUT FORMAT CONSISTENCY
# ══════════════════════════════════════════════════════════════════
section "Output Format"

# JSON errors have ok:false
out=$("$CLI" --output json foobar 2>&1)
assert_json "error envelope has ok:false" "$out" ".ok" "false"
assert_json "error envelope has error field" "$out" ".error" "Unknown command 'foobar'. Run 'godaddy --help' for usage."
assert_json "error envelope has code" "$out" ".code" "1"

# Structured validation errors
out=$("$CLI" --output json --dry-run add example.com INVALID @ test 2>&1)
assert_json "validation error is structured" "$out" ".ok" "false"

# Text mode errors don't have JSON
out=$("$CLI" --output text foobar 2>&1)
assert_contains "text error has 'Error:'" "Error:" "$out"
assert_not_contains "text error has no JSON braces" '"ok"' "$out"

# No ANSI colors in JSON mode
out=$("$CLI" --output json foobar 2>&1)
assert_not_contains "no ANSI in JSON errors" $'\033' "$out"

# ══════════════════════════════════════════════════════════════════
# FLAG PARSING EDGE CASES
# ══════════════════════════════════════════════════════════════════
section "Flag Parsing"

# --output= equals syntax
out=$("$CLI" --output=text --version 2>&1)
assert_eq "--output= syntax" "godaddy v2.0.0" "$out"

# --fields= equals syntax
out=$("$CLI" --output json --dry-run --fields=type,name add example.com A @ 1.2.3.4 2>&1)
assert_json "--fields= with dry-run" "$out" ".dry_run" "true"

# Flags before and after command
out=$("$CLI" --output json --dry-run add example.com A @ 1.2.3.4 2>&1)
assert_json "flags before command" "$out" ".dry_run" "true"

# --limit= equals syntax
out=$("$CLI" --output json --limit=5 schema 2>&1)
assert_json "--limit= doesn't break schema" "$out" ".name" "godaddy"

# ══════════════════════════════════════════════════════════════════
# CREDENTIALS
# ══════════════════════════════════════════════════════════════════
section "Credentials"

# Commands that need API fail without creds
out=$(unset GODADDY_KEY GODADDY_SECRET; "$CLI" --output json list example.com 2>&1)
assert_contains "list without creds fails" "GODADDY_KEY and GODADDY_SECRET" "$out"

# Schema doesn't need creds
out=$(unset GODADDY_KEY GODADDY_SECRET; "$CLI" schema 2>&1)
assert_json "schema works without creds" "$out" ".name" "godaddy"

# Help doesn't need creds
assert_exit "help works without creds" 0 env -u GODADDY_KEY -u GODADDY_SECRET "$CLI" --help

# Version doesn't need creds
assert_exit "version works without creds" 0 env -u GODADDY_KEY -u GODADDY_SECRET "$CLI" --version

# ══════════════════════════════════════════════════════════════════
# SUMMARY
# ══════════════════════════════════════════════════════════════════
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
if [[ "$FAIL" -eq 0 ]]; then
    printf '\033[32m%d/%d tests passed\033[0m\n' "$PASS" "$TOTAL"
else
    printf '\033[31m%d/%d tests passed (%d failed)\033[0m\n' "$PASS" "$TOTAL" "$FAIL"
fi
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
[[ "$FAIL" -gt 0 ]] && exit 1
exit 0
