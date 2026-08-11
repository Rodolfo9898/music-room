#!/bin/sh
# Reads a .env-style file (KEY=VALUE per line) and exports each variable into
# the *current* shell, skipping blank lines and full-line comments (#...).
#
# IMPORTANT: this script must be *sourced*, not executed, since `export` only
# has to affect the calling shell's environment (a child process's exports
# are discarded once it exits):
#   . app/scripts/export-env.sh [path-to-env-file]   # default: .env
#
# Values are exported literally (byte-for-byte from the file, only trimming
# a single matching pair of surrounding quotes) -- no further shell expansion
# is applied to them. This matters for secrets containing '$', '&', '#', "'",
# etc.: e.g. running `make test-e2e E2E_IMAP_PASSWORD='some$secret'` would
# have GNU Make itself re-expand `$secret` (usually to nothing) before the
# recipe ever runs, silently corrupting the value. Reading straight from a
# file via this script avoids that entirely.

# Best-effort warning if this script was executed instead of sourced: when
# sourced, $0 stays the invoking shell's own name (e.g. "bash"/"dash/"sh"),
# it only equals this script's own path when run as its own process.
case "$0" in
	*export-env.sh)
		echo "export-env.sh must be *sourced* (e.g. '. $0'), not executed directly -- otherwise the exported variables are lost when this script's process exits." >&2
		exit 1
		;;
esac

env_file="${1:-.env}"

if [ ! -f "$env_file" ]; then
	echo "export-env.sh: $env_file not found" >&2
	return 1
fi

while IFS= read -r raw_line || [ -n "$raw_line" ]; do
	# Trim leading/trailing whitespace.
	line=$(printf '%s' "$raw_line" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')

	# Skip blank lines and full-line comments.
	case "$line" in
		'' | '#'*) continue ;;
	esac

	# Only accept lines that look like KEY=VALUE, with KEY a valid shell
	# identifier (letters/underscore first, then letters/digits/underscore).
	case "$line" in
		[A-Za-z_]*=*) ;;
		*) continue ;;
	esac

	key=${line%%=*}
	case "$key" in
		*[!A-Za-z0-9_]*) continue ;;
	esac
	value=${line#*=}

	# Strip one matching pair of surrounding quotes, same convention as
	# docker's env_file / dotenv (e.g. EMAILPASS="a#b" -> a#b).
	case "$value" in
		\"*\") value=${value#\"} value=${value%\"} ;;
		\'*\') value=${value#\'} value=${value%\'} ;;
	esac

	export "$key=$value"
done < "$env_file"
