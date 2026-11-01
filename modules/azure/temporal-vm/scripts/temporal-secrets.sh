#!/usr/bin/env bash
# Read the gate's keys and certificate from Key Vault and write the two files
# the gate (Envoy) loads them from. Runs before the gate starts and every 5
# minutes from temporal-secrets.timer.
#
# The VM's identity gets a Key Vault token from the instance metadata service.
# For each key entry the gate accepts the two newest enabled versions, so a
# client can move to a new version before the old one is disabled. The
# certificate entry holds the certificate, its chain and its private key, as
# PEM or as base64 PKCS#12.
#
# The gate watches the cert and routes directories and reloads a file when a
# new one is moved in (file-based xDS): the certificate as an SDS secret, the
# keys as the route table. The rename is atomic, and a reload keeps open
# connections. A file is replaced only when its content changed. On any error
# the old files stay and the script exits non-zero; the next run tries again.
#
# With --wait (the gate's start step) it retries until a run succeeds, or goes
# on at once when an earlier run left both files.
#
# It never prints a key, the private key or the token. The TEMPORAL_EDGE_*
# variables exist for tests; the units do not set them.
set -euo pipefail

conf_dir="${TEMPORAL_EDGE_CONF_DIR:-/etc/temporal-edge}"
state_dir="${TEMPORAL_EDGE_STATE_DIR:-/var/lib/temporal-edge}"
imds="${TEMPORAL_EDGE_IMDS:-http://169.254.169.254}"
edge_uid=65532
cert_file="$state_dir/cert/cert.json"
routes_file="$state_dir/routes/routes.json"

if [ "${1:-}" = "--wait" ]; then
  delay=15
  until "$0"; do
    if [ -s "$cert_file" ] && [ -s "$routes_file" ]; then
      echo "refresh failed; the gate starts with the files of the last good refresh"
      exit 0
    fi
    echo "refresh failed and no files exist yet, retrying in $delay seconds"
    sleep "$delay"
    delay=$((delay * 2))
    if [ "$delay" -gt 300 ]; then delay=300; fi
  done
  exit 0
fi

# KEY_VAULT_URI, IDENTITY_CLIENT_ID and the four entry names.
# shellcheck source=/dev/null
. "$conf_dir/edge.conf"

umask 077
as_root=false
if [ "$(id -u)" = 0 ]; then as_root=true; fi

install -d -m 0755 "$state_dir"
for d in "$state_dir/cert" "$state_dir/routes"; do
  if $as_root; then
    install -d -m 0700 -o "$edge_uid" -g "$edge_uid" "$d"
  else
    install -d -m 0700 "$d"
  fi
done

# One run at a time: the timer and the gate's start step may overlap.
if command -v flock >/dev/null 2>&1; then
  exec 9>"$state_dir/.lock"
  flock 9
fi

work=$(mktemp -d "$state_dir/.work.XXXXXX")
trap 'rm -rf "$work"' EXIT

# The token goes to a header file, not to the command line.
curl -sS --fail --max-time 30 --retry 5 --retry-delay 2 -H Metadata:true \
  "$imds/metadata/identity/oauth2/token?api-version=2018-02-01&resource=https%3A%2F%2Fvault.azure.net&client_id=$IDENTITY_CLIENT_ID" |
  jq -er '"Authorization: Bearer " + .access_token' >"$work/auth"

kv() {
  curl -sS --fail --max-time 30 --retry 3 --retry-delay 2 -H @"$work/auth" "$1"
}

# IDs of the two newest versions of a secret that are enabled and inside
# their not-before and expiry dates, newest first.
newest_versions() {
  local url="$KEY_VAULT_URI/secrets/$1/versions?api-version=7.4&maxresults=25"
  : >"$work/versions"
  while [ -n "$url" ]; do
    kv "$url" >"$work/page"
    jq -c '.value[]' "$work/page" >>"$work/versions"
    url=$(jq -r '.nextLink // empty' "$work/page")
  done
  jq -rs --argjson now "$(date +%s)" '
    map(select(.attributes.enabled == true
      and (.attributes.nbf // 0) <= $now
      and (.attributes.exp // ($now + 1)) > $now))
    | sort_by(.attributes.created) | reverse | .[0:2][] | .id' "$work/versions"
}

# --- Keys -------------------------------------------------------------------

: >"$work/keys"
add_keys() {
  local role="$1" entry="$2" id n=0
  newest_versions "$entry" >"$work/ids"
  while read -r id; do
    kv "$id?api-version=7.4" >"$work/secret"
    # A key goes into a header match: one token of bearer characters.
    if jq -e '.value | test("^[A-Za-z0-9._~+/=-]{32,}$")' "$work/secret" >/dev/null; then
      jq -c --arg role "$role" --arg entry "$entry" --arg version "${id##*/}" \
        '{role: $role, entry: $entry, version: $version, key: .value}' "$work/secret" >>"$work/keys"
      n=$((n + 1))
    else
      echo "skipped version ${id##*/} of $entry: a key must be 32 or more letters, digits or ._~+/=-" >&2
    fi
  done <"$work/ids"
  if [ "$n" = 0 ]; then
    echo "$entry has no enabled version that can be a key" >&2
    return 1
  fi
}

add_keys app "$API_SERVER_KEY_ENTRY"
add_keys app "$AGENTS_KEY_ENTRY"
add_keys runner "$RUNNER_KEY_ENTRY"

# The runner key must not open the app routes.
if ! jq -se '([.[] | select(.role == "runner") | .key]) as $r
  | all(.[] | select(.role == "app"); .key as $k | ($r | any(. == $k)) | not)' "$work/keys" >/dev/null; then
  echo "a version of $RUNNER_KEY_ENTRY has the same value as an app key; refusing it" >&2
  exit 1
fi

# The method names, one per line, as a JSON list.
methods() { jq -Rn '[inputs | select(length > 0)]' "$conf_dir/$1"; }

# Routes in order: health with any key, the runner's calls with a runner key,
# the denied calls for everyone, the rest of WorkflowService with an app key,
# and 401 for all else. The route name is the key's role, entry and version,
# which the access log records in place of the key. A method is matched by its
# exact path, one route each, not by one regex for the list: Envoy 1.35 refuses
# a regex over its program size limit (100), and the whole file with it.
jq -s --argjson runner "$(methods runner-methods)" --argjson denied "$(methods denied-methods)" '
  def fwd($name; $match): {
    name: $name,
    match: $match,
    request_headers_to_remove: ["authorization"],
    route: {cluster: "temporal", timeout: "0s", idle_timeout: "3600s"}
  };
  def bearer($k): [{name: "authorization", string_match: {exact: ("Bearer " + $k.key)}}];
  def ident($k): $k.role + "/" + $k.entry + "/" + $k.version;
  def call($m): "/temporal.api.workflowservice.v1.WorkflowService/" + $m;
  def refuse($name; $match; $body): {
    name: $name,
    match: $match,
    direct_response: {status: 401, body: {inline_string: $body}}
  };
  . as $keys
  | {
      name: "temporal",
      virtual_hosts: [{
        name: "temporal",
        domains: ["*"],
        routes: (
          [$keys[] | fwd("health/" + ident(.); {prefix: "/grpc.health.v1.Health/", headers: bearer(.)})]
          + [$keys[] | select(.role == "runner") as $k | $runner[] | fwd(ident($k); {path: call(.), headers: bearer($k)})]
          + [$denied[] | refuse("denied"; {path: call(.)}; "call not allowed\n")]
          + [$keys[] | select(.role == "app") | fwd(ident(.); {prefix: "/temporal.api.workflowservice.v1.WorkflowService/", headers: bearer(.)})]
          + [refuse("unauthorized"; {prefix: "/"}; "key missing or wrong, or call not allowed for this key\n")]
        )
      }]
    }' "$work/keys" >"$work/routes"

# --- Certificate ------------------------------------------------------------

kv "$KEY_VAULT_URI/secrets/$CERTIFICATE_ENTRY?api-version=7.4" >"$work/cert-secret"
if [ "$(jq -r '.contentType // ""' "$work/cert-secret")" = "application/x-pkcs12" ]; then
  jq -r .value "$work/cert-secret" | base64 -d >"$work/cert.pfx"
  # Key Vault exports PKCS#12 without a password. Older files use ciphers
  # that OpenSSL 3 keeps in its legacy provider.
  openssl pkcs12 -in "$work/cert.pfx" -passin pass: -nodes -out "$work/all.pem" 2>/dev/null ||
    openssl pkcs12 -legacy -in "$work/cert.pfx" -passin pass: -nodes -out "$work/all.pem"
else
  jq -r .value "$work/cert-secret" >"$work/all.pem"
fi

openssl pkey -in "$work/all.pem" -out "$work/key.pem"
openssl pkey -in "$work/key.pem" -pubout -out "$work/key.pub"
awk -v dir="$work" '
  /-----BEGIN CERTIFICATE-----/ { n++; f = dir "/cert-" n ".pem" }
  f { print > f }
  /-----END CERTIFICATE-----/ { close(f); f = "" }' "$work/all.pem"

# The certificate of the private key goes first, then the rest of the chain.
leaf=""
for c in "$work"/cert-*.pem; do
  [ -e "$c" ] || break
  if openssl x509 -in "$c" -noout -pubkey | cmp -s - "$work/key.pub"; then
    leaf="$c"
    break
  fi
done
if [ -z "$leaf" ]; then
  echo "$CERTIFICATE_ENTRY has no certificate for its private key" >&2
  exit 1
fi
cp "$leaf" "$work/chain.pem"
for c in "$work"/cert-*.pem; do
  if [ "$c" != "$leaf" ]; then cat "$c" >>"$work/chain.pem"; fi
done
if ! openssl x509 -in "$leaf" -noout -checkend 0 >/dev/null; then
  echo "warning: the certificate in $CERTIFICATE_ENTRY has expired" >&2
fi

jq -n --rawfile chain "$work/chain.pem" --rawfile key "$work/key.pem" '{
  name: "temporal-cert",
  tls_certificate: {certificate_chain: {inline_string: $chain}, private_key: {inline_string: $key}}
}' >"$work/cert"

# --- Write ------------------------------------------------------------------

# Wrap a resource in a discovery response, versioned by its content, and move
# it into place if it changed.
publish() {
  local label="$1" src="$2" dest="$3" type="$4" version
  version=$(openssl dgst -sha256 <"$src" | awk '{ print substr($NF, 1, 16) }')
  jq --arg version "$version" --arg type "$type" \
    '{version_info: $version, resources: [{"@type": $type} + .]}' "$src" >"$src.xds"
  if [ -s "$dest" ] && cmp -s "$src.xds" "$dest"; then
    echo "$label unchanged"
    return 0
  fi
  chmod 0600 "$src.xds"
  if $as_root; then chown "$edge_uid:$edge_uid" "$src.xds"; fi
  mv -f "$src.xds" "$dest"
  echo "$label updated"
}

publish "certificate ($(openssl x509 -in "$leaf" -noout -subject -enddate | paste -s -d ' ' -))" \
  "$work/cert" "$cert_file" type.googleapis.com/envoy.extensions.transport_sockets.tls.v3.Secret
publish "routes (keys $(jq -rs 'map(.role + "/" + .entry + "/" + .version) | join(", ")' "$work/keys"))" \
  "$work/routes" "$routes_file" type.googleapis.com/envoy.config.route.v3.RouteConfiguration
