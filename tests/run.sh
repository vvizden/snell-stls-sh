#!/usr/bin/env bash
set -euo pipefail
export LC_ALL=C
ROOT=$(cd "$(dirname "$0")/.." && pwd)
. "$ROOT/snell.sh"
TEST_ROOT=$(mktemp -d)
trap 'rm -rf "$TEST_ROOT"' EXIT
passed=0
fail() { printf 'FAIL: %s\n' "$*" >&2; exit 1; }
eq() { [[ "$1" == "$2" ]] || fail "expected [$2], got [$1]"; }
yes_cmd() { "$@" || fail "command should succeed: $*"; }
no_cmd() { if ( "$@" ) >/dev/null 2>&1; then fail "command should fail: $*"; fi; }
case_run() { ( "$2" ); passed=$((passed+1)); printf 'PASS %s\n' "$1"; }

version_order() {
  local v key previous= versions=(5.0.1 5.1.0b1 5.1.0rc 5.1.0 6.0.0b1 6.0.0b2 6.0.0b4 6.0.0b10 6.0.0rc 6.0.0rc2 6.0.0rc10 6.0.0 6.0.1 6.1.0b1)
  for v in "${versions[@]}"; do
    key=$(version_key "$v") || fail "parse $v"
    [[ -z "$previous" || "$key" > "$previous" ]] || fail "incorrect order at $v"
    previous=$key
  done
  eq "$(version_key 6.0.0rc)" "$(version_key 6.0.0rc1)"
  eq "$(version_key v6.0.0b4)" "$(version_key 6.0.0b4)"
  yes_cmd binary_report_matches 6.0.0rc2 6.0.0
  yes_cmd binary_report_matches 6.0.0b4 6.0.0
  no_cmd binary_report_matches 6.0.0rc2 5.0.1
  no_cmd binary_report_matches 6.0.0rc2 6.0.0b4
  no_cmd binary_report_matches 6.0.0 6.0.0rc2
  for v in '' 6 6.0 6.0.0garbage 6.0.0rc-2 6.0.0bfoo '6.0.0;id' 1000000.0.0; do no_cmd version_key "$v"; done
}
record() { printf '%s\t%s\t%s/snell-server-v%s-linux-%s.zip\n' "$1" "$2" "$DOWNLOAD_BASE" "$1" "$2"; }
catalog_parse() {
  local text catalog
  text='<a href="https://dl.nssurge.com/snell/snell-server-v6.0.0rc2-linux-amd64.zip">RC2</a>
https://dl.nssurge.com/snell/snell-server-v6.0.0rc-linux-amd64.zip
https://dl.nssurge.com/snell/snell-server-v5.0.1-linux-amd64.zip
https://dl.nssurge.com/snell/snell-server-v6.0.0rc2-linux-amd64.zip
https://evil.example/snell-server-v99.0.0-linux-amd64.zip'
  catalog=$(printf '%s\n' "$text" | parse_releases)
  eq "$(printf '%s\n' "$catalog" | wc -l | tr -d ' ')" 3
  eq "$(select_release "$catalog" stable amd64)" "5.0.1"$'\t'"$DOWNLOAD_BASE/snell-server-v5.0.1-linux-amd64.zip"
  eq "$(select_release "$catalog" rc amd64)" "6.0.0rc2"$'\t'"$DOWNLOAD_BASE/snell-server-v6.0.0rc2-linux-amd64.zip"
  eq "$(select_release "$catalog" beta amd64)" "$(select_release "$catalog" rc amd64)"
  no_cmd select_release "$catalog" beta aarch64
  no_cmd parse_releases <<<'https://dl.nssurge.com/snell/snell-server-v6.0.0unexpected-linux-amd64.zip'
}
channel_selection() {
  local catalog
  catalog=$(record 5.0.1 aarch64; record 6.0.0rc2 amd64; record 6.0.0 amd64; record 6.1.0b1 amd64; record 6.0.0b4 amd64)
  eq "$(select_release "$catalog" rc amd64 | cut -f1)" 6.0.0
  eq "$(select_release "$catalog" beta amd64 | cut -f1)" 6.1.0b1
  no_cmd select_release "$catalog" stable aarch64
  catalog=$(printf '%s\n' "$catalog"; record 7.0.0 amd64)
  no_cmd select_release "$catalog" stable amd64
  yes_cmd channel_allows stable 5.0.1
  no_cmd channel_allows stable 6.0.0rc2
  no_cmd channel_allows rc 6.1.0b1
  yes_cmd channel_allows beta 6.0.0
}
fallback_discovery() {
  local calls="$TEST_ROOT/fetch-calls"
  curl() {
    printf '%s\n' "$*" >>"$calls"
    case "${*: -1}" in *.md) printf '<html>login</html>\n' ;; *) printf '%s/snell-server-v6.0.0rc2-linux-amd64.zip\n' "$DOWNLOAD_BASE" ;; esac
  }
  eq "$(fetch_catalog | cut -f1)" 6.0.0rc2
  eq "$(wc -l <"$calls" | tr -d ' ')" 2
  curl() { return 22; }
  no_cmd fetch_catalog
}
input_contract() {
  local p s
  for p in 1 443 65535 00080; do yes_cmd valid_port "$p"; done
  for p in 0 65536 -1 1.1 abc 9999999; do no_cmd valid_port "$p"; done
  for s in 127.0.0.1 1.2.3.4 vpn.example.com xn--bcher-kva.example; do yes_cmd valid_server "$s"; done
  for s in 999.1.1.1 1.2.3 'x,psk=foo' '$(id)' 'x y' '-bad.example' 'https://example.com' '../etc' '.example.com'; do no_cmd valid_server "$s"; done
  no_cmd parse_args install --channel beta --version 6.0.0b4
  no_cmd parse_args upgrade --server example.com
  no_cmd parse_args upgrade --allow-downgrade
  no_cmd parse_args status --purge
  no_cmd parse_args install --version 7.0.0
  no_cmd parse_args install --port
}
config_versions() {
  local v server_config snippet
  SERVER=example.com PORT=443 PSK=abcdefghijklmnopqrstuvwxyz0123456789
  for v in 5.0.1 6.0.0b1 6.0.0b2 6.0.0b4 6.0.0rc2 6.0.0; do
    TARGET=$v
    server_config=$(render_server_config); snippet=$(render_surge_config)
    [[ "$server_config" == *'listen = 0.0.0.0:443'* && "$server_config" == *'ipv6 = false'* ]] || fail 'server defaults'
    [[ "$server_config" != *mode* && "$server_config" != *dns-ip-preference* ]] || fail 'new parameter leaked into old version'
    [[ "$snippet" == *"version=${v%%.*}, reuse=true, block-quic=on" ]] || fail 'client protocol version mismatch'
    [[ "$snippet" != *shadow* && "$snippet" != *tfo* ]] || fail 'legacy tuning in config'
  done
}

# State-machine tests run as root in Linux, using real files, ownership, hashing,
# locks and pointers. Only the systemd interaction and health result are mocked.
setup_snapshots() {
  BASE="$TEST_ROOT/state-$RANDOM"; mkdir -m 755 "$BASE"; mkdir -m 755 "$BASE/generations"
  printf '%s\n' "$OWNER" >"$BASE/.owner"
  UNIT="$BASE/unit" MANAGER="$BASE/manager"; SYSTEM_LOG="$BASE/system-log"
  printf '# snellctl-managed-v1\n' >"$UNIT"; cp "$UNIT" "$MANAGER"
  local id v hash
  for id in g-old g-new; do
    mkdir -m 755 "$BASE/generations/$id"; printf '%s\n' "$OWNER" >"$BASE/generations/$id/.owner"
    if [[ "$id" == g-old ]]; then v=5.0.1; else v=6.0.0rc2; fi
    printf '%s\n' "$v" >"$BASE/generations/$id/snell-server"
    printf 'psk = same-secret\n' >"$BASE/generations/$id/snell-server.conf"
    printf 'client-%s\n' "$v" >"$BASE/generations/$id/surge.conf"
    jq -n --arg version "$v" --arg binary "$(sha256sum "$BASE/generations/$id/snell-server" | cut -d' ' -f1)" \
      --arg config "$(sha256sum "$BASE/generations/$id/snell-server.conf" | cut -d' ' -f1)" \
      --arg surge "$(sha256sum "$BASE/generations/$id/surge.conf" | cut -d' ' -f1)" \
      '{schema:1,version:$version,channel:"stable",settings:{server:"example.com",port:443},hashes:{"snell-server":$binary,"snell-server.conf":$config,"surge.conf":$surge}}' >"$BASE/generations/$id/metadata.json"
  done
  printf '{"current":"g-old","previous":null,"installed":true}\n' | atomic_json "$BASE/state.json"
  activate_pointer g-old
  systemctl() { printf '%s\n' "$*" >>"$SYSTEM_LOG"; return 0; }
  health_check() { [[ "$1" != "${FAIL_HEALTH:-none}" ]]; }
}
snapshot_success() {
  setup_snapshots
  switch_generation g-new
  eq "$(current_id)" g-new
  eq "$(readlink "$BASE/current")" generations/g-new
  eq "$(jq -r .previous "$BASE/state.json")" g-old
  [[ ! -e "$BASE/transaction.json" ]] || fail 'pending transaction after commit'
  switch_generation g-old
  eq "$(cat "$BASE/current/surge.conf")" client-5.0.1
  eq "$(jq -r .previous "$BASE/state.json")" g-new
}
snapshot_failure() {
  setup_snapshots
  FAIL_HEALTH=g-new
  no_cmd switch_generation g-new
  eq "$(current_id)" g-old
  eq "$(readlink "$BASE/current")" generations/g-old
  eq "$(cat "$BASE/current/surge.conf")" client-5.0.1
  [[ ! -e "$BASE/transaction.json" ]] || fail 'transaction not cleared after recovery'
  grep -q 'stop snell-server.service' "$SYSTEM_LOG" || fail 'runtime path not exercised'
}
interrupted_transaction() {
  setup_snapshots
  jq -n --argjson old "$(cat "$BASE/state.json")" '{old:$old,target:"g-new"}' | atomic_json "$BASE/transaction.json"
  activate_pointer g-new
  printf '{"current":"g-new","previous":"g-old","installed":true}\n' | atomic_json "$BASE/state.json"
  recover_transaction
  eq "$(current_id)" g-old
  eq "$(readlink "$BASE/current")" generations/g-old
  yes_cmd verify_generation g-old
}
integrity_and_ownership() {
  setup_snapshots
  yes_cmd verify_generation g-old
  printf 'tamper\n' >>"$BASE/generations/g-old/surge.conf"
  no_cmd verify_generation g-old
  no_cmd generation_dir ../outside
  ln -s "$BASE/generations/g-new" "$BASE/generations/g-link"
  no_cmd generation_dir g-link
  printf '# foreign unit\n' >"$UNIT"
  no_cmd check_owned_files
  # A rejected ownership check must not let EXIT recovery mutate that service.
  jq -n --argjson old "$(cat "$BASE/state.json")" '{old:$old,target:"g-new"}' | atomic_json "$BASE/transaction.json"
  protected_cleanup_probe() {
    LOCKED=1 OWNERSHIP_CHECKED=0
    trap cleanup_exit EXIT
    check_owned_files
  }
  no_cmd protected_cleanup_probe
  [[ -e "$BASE/transaction.json" && ! -e "$SYSTEM_LOG" ]] || fail 'ownership rejection triggered recovery side effects'
}
exclusive_lock() {
  LOCK_DIR="$TEST_ROOT/lock-$RANDOM"
  acquire_lock
  if bash -c '. "$1/snell.sh"; LOCK_DIR="$2"; acquire_lock' _ "$ROOT" "$LOCK_DIR" 9>&- >/dev/null 2>&1; then fail 'second operation acquired lock'; fi
  exec 9>&-
  yes_cmd bash -c '. "$1/snell.sh"; LOCK_DIR="$2"; acquire_lock' _ "$ROOT" "$LOCK_DIR"
}
checksum_contract() {
  WORK="$TEST_ROOT/checksum"; mkdir "$WORK"
  printf archive >"$WORK/release.zip"
  local test_checksum test_code=200 digest
  digest=$(sha256sum "$WORK/release.zip"); test_checksum=${digest%% *}
  curl() { printf '%s\n' "$test_checksum" >"$WORK/upstream.sha256"; printf '%s %s/file.zip.sha256' "$test_code" "$DOWNLOAD_BASE"; }
  yes_cmd verify_upstream_checksum "$DOWNLOAD_BASE/file.zip" "$WORK/release.zip"
  eq "$CHECKSUM_SOURCE" official-sidecar
  test_checksum=$(printf '%064d' 0)
  no_cmd verify_upstream_checksum "$DOWNLOAD_BASE/file.zip" "$WORK/release.zip"
  test_checksum=malformed
  no_cmd verify_upstream_checksum "$DOWNLOAD_BASE/file.zip" "$WORK/release.zip"
  test_code=404
  yes_cmd verify_upstream_checksum "$DOWNLOAD_BASE/file.zip" "$WORK/release.zip"
  eq "$CHECKSUM_SOURCE" local-only
  test_code=503
  no_cmd verify_upstream_checksum "$DOWNLOAD_BASE/file.zip" "$WORK/release.zip"
  curl() { return 28; }
  no_cmd verify_upstream_checksum "$DOWNLOAD_BASE/file.zip" "$WORK/release.zip"
}
staging_failures() {
  setup_snapshots
  local fault before
  TARGET=6.0.0rc2 ARCH=amd64 TARGET_URL="$DOWNLOAD_BASE/test.zip"
  before=$(readlink "$BASE/current")
  # Keep actual ZIP inspection and file(1); mock only network and account setup.
  chown() { :; }
  verify_upstream_checksum() { CHECKSUM_SOURCE=local-only; }
  download_archive() {
    case "$fault" in
      interrupted) return 28 ;;
      corrupt) printf bad >"$2" ;;
      missing) ( cd "$TEST_ROOT"; printf test >other; zip -q "$2" other ) ;;
      wrong-arch) ( cd "$TEST_ROOT"; cp /bin/true snell-server; zip -q "$2" snell-server ) ;;
    esac
  }
  for fault in interrupted corrupt missing wrong-arch; do
    if [[ "$fault" == wrong-arch ]]; then
      case "$(uname -m)" in aarch64) ARCH=amd64 ;; *) ARCH=aarch64 ;; esac
    fi
    no_cmd stage_generation
    eq "$(readlink "$BASE/current")" "$before"
    [[ ! -e "$SYSTEM_LOG" ]] || fail 'staging failure touched systemd'
    yes_cmd verify_generation g-old
  done
}
recovery_failure() {
  setup_snapshots
  jq -n --argjson old "$(cat "$BASE/state.json")" '{old:$old,target:"g-new"}' | atomic_json "$BASE/transaction.json"
  activate_pointer g-new
  FAIL_HEALTH=g-old
  no_cmd recover_transaction
  [[ -e "$BASE/transaction.json" ]] || fail 'failed recovery discarded transaction'
  prune_generations
  [[ -e "$BASE/generations/g-new" ]] || fail 'pending transaction pruned snapshot'
}

bash -n "$ROOT/snell.sh"
case_run 'full prerelease numeric ordering and malformed inputs' version_order
case_run 'official parser and original RC truncation regression' catalog_parse
case_run 'maturity ceilings, missing architecture and unknown major' channel_selection
case_run 'Markdown-to-HTML fallback and network failure' fallback_discovery
case_run 'CLI and endpoint validation' input_contract
case_run 'v5 / early v6 beta / RC / final configuration generation' config_versions
if [[ $(uname -s) == Linux && $EUID == 0 ]]; then
  case_run 'complete snapshot switch and offline rollback' snapshot_success
  case_run 'failed startup restores binary/config/export/state' snapshot_failure
  case_run 'interruption between state update and commit' interrupted_transaction
  case_run 'snapshot integrity, traversal and foreign-unit rejection' integrity_and_ownership
  case_run 'exclusive operation lock' exclusive_lock
  case_run 'official checksum, absence, mismatch and network failures' checksum_contract
  case_run 'download, corrupt ZIP, missing member and wrong architecture preserve deployment' staging_failures
  case_run 'failed recovery retains transaction and generations' recovery_failure
else
  printf 'NOT RUN: Linux/root state-machine tests. Run tests in the documented Linux container.\n'
fi
printf '%s test groups passed.\n' "$passed"
