#!/usr/bin/env bash
#
# Runs (or builds) Steward with the OSM OAuth client id from
# secrets/vault.env, which is gitignored and never committed.
#
# There is one id, because there is one OpenStreetMap: both configurations in
# lib/src/osm/osm_environment.dart use the production hosts and the production
# OAuth app. What `osmEnvironment` decides is whether a submission actually
# writes, which is a build-time constant this script never needs to know about.
#
# The client *secret* in that file is deliberately NOT passed. Steward is a
# public OAuth client — a browser app with nowhere to keep a secret — and uses
# PKCE instead. Anything handed to the web build is readable by anyone who
# opens devtools, so a secret passed here would not be a secret.
#
#   tool/run.sh                 # flutter run on 127.0.0.1:5000
#   tool/run.sh build web       # any other flutter subcommand
set -euo pipefail

cd "$(dirname "$0")/.."
VAULT="secrets/vault.env"

if [[ ! -f "$VAULT" ]]; then
  echo "error: $VAULT not found." >&2
  echo "It holds the OSM OAuth client id — see the README's" >&2
  echo "\"OSM API environment\" section for the key it needs." >&2
  exit 1
fi

# Reads one `KEY: value` line. Tolerates `KEY=value`, surrounding whitespace,
# and quotes, because a secrets file is exactly the place a stray space goes
# unnoticed until sign-in mysteriously fails.
vault_get() {
  sed -nE "s/^[[:space:]]*$1[[:space:]]*[:=][[:space:]]*[\"']?([^\"'[:space:]]+).*/\1/p" \
    "$VAULT" | head -n1
}

CLIENT_ID="$(vault_get OSM_OAUTH_CLIENT_ID)"

if [[ -z "$CLIENT_ID" ]]; then
  echo "error: OSM_OAUTH_CLIENT_ID is missing or empty in $VAULT" >&2
  exit 1
fi

DEFINES=(--dart-define="OSM_CLIENT_ID=$CLIENT_ID")

if [[ $# -eq 0 ]]; then
  # 127.0.0.1 and a fixed port on purpose: OSM matches redirect URIs exactly,
  # rejects `localhost` outright, and Flutter otherwise picks a random port.
  exec flutter run -d chrome --web-hostname 127.0.0.1 --web-port 5000 "${DEFINES[@]}"
fi

exec flutter "$@" "${DEFINES[@]}"
