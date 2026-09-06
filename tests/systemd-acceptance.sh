#!/usr/bin/env bash
# Destructive acceptance suite: disposable systemd container ONLY.
set -euo pipefail
[[ ${SNELLCTL_DISPOSABLE_TEST:-} == YES && -f /.dockerenv ]] || { echo 'Requires a disposable Docker container and SNELLCTL_DISPOSABLE_TEST=YES' >&2; exit 1; }
ROOT=$(cd "$(dirname "$0")/.." && pwd)
[[ ! -e /opt/snellctl ]] || { echo 'Requires a fresh container' >&2; exit 1; }
. "$ROOT/snell.sh"
expect_fail() { if ( "$@" ) > /tmp/snellctl-expected-failure.log 2>&1; then echo "Unexpected success: $*" >&2; exit 1; fi; }
assert_running() { health_check "$(current_id)"; }
assert_version() { [[ $(jq -r .version "$BASE/current/metadata.json") == "$1" ]]; }
# Occupied port must not be killed or adopted.
systemd-socket-activate -l 443 /bin/cat >/tmp/snellctl-port-test.log 2>&1 &
listener=$!
trap 'kill "$listener" 2>/dev/null || true' EXIT
sleep 1
expect_fail bash "$ROOT/snell.sh" install --version 5.0.1 --server 127.0.0.1 --yes
kill -0 "$listener"
[[ ! -e "$BASE" ]]
kill "$listener"; wait "$listener" || true
trap - EXIT
bash "$ROOT/snell.sh" install --version 5.0.1 --server 127.0.0.1 --non-interactive --yes
assert_running; assert_version 5.0.1
original_psk=$(sed -n 's/^psk = //p' "$BASE/current/snell-server.conf")
[[ ${#original_psk} == 64 ]]
[[ $(stat -c '%U:%G:%a' "$BASE/current/snell-server.conf") == root:snell:640 ]]
[[ $(stat -c '%U:%a' "$BASE/current/surge.conf") == root:600 ]]
expect_fail runuser -u nobody -- cat "$BASE/current/surge.conf"
snellctl upgrade --channel rc --yes
assert_running; assert_version 6.0.0rc2
[[ $(jq -r .channel "$BASE/current/metadata.json") == rc ]]
expect_fail snellctl upgrade --channel stable --yes
assert_running; assert_version 6.0.0rc2
# Exact version downgrade preserves rc channel and PSK.
snellctl upgrade --version 6.0.0b4 --allow-downgrade --yes
assert_running; assert_version 6.0.0b4
[[ $(jq -r .channel "$BASE/current/metadata.json") == rc ]]
[[ $(sed -n 's/^psk = //p' "$BASE/current/snell-server.conf") == "$original_psk" ]]
# No network function can be used by rollback.
( curl() { echo 'Unexpected network access during rollback' >&2; return 99; }; export -f curl; snellctl rollback --yes )
assert_running; assert_version 6.0.0rc2
# A real server startup failure must restore the entire prior snapshot.
old=$(current_id)
new=$(jq -r .previous "$BASE/state.json")
config="$BASE/generations/$new/snell-server.conf"
printf '[snell-server]\nlisten = invalid\n' >"$config"
hash=$(sha256sum "$config"); hash=${hash%% *}
jq --arg hash "$hash" '.hashes["snell-server.conf"]=$hash' "$BASE/generations/$new/metadata.json" > /tmp/snellctl-meta
cat /tmp/snellctl-meta >"$BASE/generations/$new/metadata.json"
expect_fail bash -c '. "$1/snell.sh"; set -Eeuo pipefail; switch_generation "$2"' _ "$ROOT" "$new"
[[ $(current_id) == "$old" ]]
assert_running
# Interrupt a real in-progress deployment with SIGTERM; EXIT cleanup restores it.
bash -c '. "$1/snell.sh"; set -Eeuo pipefail; acquire_lock; check_owned_files; trap cleanup_exit EXIT; trap "exit 143" TERM; switch_generation "$2"' _ "$ROOT" "$new" >/tmp/snellctl-signal.log 2>&1 &
operation=$!
for ((i=0; i<100; i++)); do
  [[ $(readlink "$BASE/current") != "generations/$new" ]] || break
  sleep 0.1
done
[[ -e "$BASE/transaction.json" ]]
kill -TERM "$operation"
if wait "$operation"; then echo 'Interrupted deployment unexpectedly succeeded' >&2; exit 1; fi
[[ $(current_id) == "$old" && ! -e "$BASE/transaction.json" ]]
assert_running
# Simulate SIGKILL after pointer switch, before state commit; next operation recovers.
jq -n --argjson old "$(cat "$BASE/state.json")" --arg target "$new" '{old:$old,target:$target}' | atomic_json "$BASE/transaction.json"
systemctl stop "$SERVICE"
activate_pointer "$new"
snellctl status
[[ $(current_id) == "$old" && ! -e "$BASE/transaction.json" ]]
assert_running
systemctl restart "$SERVICE"
assert_running
snellctl uninstall --yes
[[ ! -e "$BASE" && ! -e "$UNIT" && ! -e "$MANAGER" ]]
! getent passwd snell >/dev/null
printf 'PASS: real systemd acceptance (%s / %s)\n' "$(. /etc/os-release; echo "$PRETTY_NAME")" "$(uname -m)"
