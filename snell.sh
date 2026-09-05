#!/usr/bin/env bash
# snellctl-managed-v1
# Single-file installer and manager. Sourcing this file defines functions only.

MANAGER_VERSION=1.0.0
OWNER=snellctl-v1
BASE=/opt/snellctl
MANAGER=/usr/local/sbin/snellctl
UNIT=/etc/systemd/system/snell-server.service
SERVICE=snell-server.service
LOCK_DIR=/run/snellctl
NOTES=https://kb.nssurge.com/surge-knowledge-base/release-notes/snell
DOWNLOAD_BASE=https://dl.nssurge.com/snell
ARCH='' COMMAND='' CHANNEL='' EXACT='' SERVER='' PORT='' PSK=''
YES=0 NON_INTERACTIVE=0 ALLOW_DOWNGRADE=0 PURGE=0 LOCKED=0 OWNERSHIP_CHECKED=0
WORK='' TARGET='' TARGET_URL='' TARGET_CHANNEL='' NEW_GEN=''

log() { printf '%s\n' "$*"; }
warn() { printf 'Warning: %s\n' "$*" >&2; }
die() { printf 'Error: %s\n' "$*" >&2; exit 1; }
usage() {
  printf 'Manager version: %s\n' "$MANAGER_VERSION"
  cat <<'EOF'
snellctl — native Snell, one instance, complete deployment rollback

Usage: snellctl <command> [options]
       bash snell.sh <command> [options]

  versions    Discover official versions and list retained local deployments
  install     Fresh installation (default channel: stable)
  upgrade     Follow the saved channel, or choose another channel/exact version
  rollback    Restore the previous complete deployment without network access
  status      Show running version, saved channel, listener and rollback target
  export      Print the current Surge proxy line (contains the PSK; root only)
  uninstall   Remove service and command; retain snapshots unless --purge

  --channel stable|rc|beta    Maturity ceiling; install/upgrade only
  --version VERSION          Exact official version; install/upgrade only
  --allow-downgrade          Explicit downgrade; upgrade --version only
  --server IP_OR_HOSTNAME    Public IPv4 address or DNS name; install only
  --port PORT               IPv4 TCP listener (default 443); install only
  --psk PSK                 Optional 16–255 ASCII letters/digits/_/-; install only
  --non-interactive         Never prompt; install requires --server
  --yes                     Accept the displayed operation
  --purge                   Delete retained snapshots; uninstall only
  -h, --help                Show this help

stable allows final releases; rc allows final + RC; beta allows all three.
The newest complete version wins. For example beta may select an RC or final.
No background updates, firewall changes, ShadowTLS or legacy-install migration.
EOF
}

parse_args() {
  COMMAND=${1:-help}; [[ $# -eq 0 ]] || shift
  case "$COMMAND" in
    help|-h|--help) usage; return 2 ;;
    versions|install|upgrade|rollback|status|export|uninstall) ;;
    *) die "Unknown command: $COMMAND" ;;
  esac
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --channel|--version|--server|--port|--psk)
        [[ $# -ge 2 && -n "$2" && "$2" != --* ]] || die "$1 requires a value"
        case "$1" in
          --channel) CHANNEL=$2 ;; --version) EXACT=$2 ;; --server) SERVER=$2 ;;
          --port) PORT=$2 ;; --psk) PSK=$2 ;;
        esac
        shift 2 ;;
      --yes) YES=1; shift ;;
      --non-interactive) NON_INTERACTIVE=1; shift ;;
      --allow-downgrade) ALLOW_DOWNGRADE=1; shift ;;
      --purge) PURGE=1; shift ;;
      -h|--help) usage; return 2 ;;
      *) die "Unknown option: $1" ;;
    esac
  done
  [[ -z "$CHANNEL" || -z "$EXACT" ]] || die "--channel and --version are mutually exclusive"
  [[ -z "$CHANNEL" || "$CHANNEL" == stable || "$CHANNEL" == rc || "$CHANNEL" == beta ]] || die "Invalid channel"
  if [[ -n "$CHANNEL$EXACT" ]]; then
    [[ "$COMMAND" == install || "$COMMAND" == upgrade ]] || die "Version selectors require install/upgrade"
  fi
  if [[ -n "$SERVER$PORT$PSK" ]]; then
    [[ "$COMMAND" == install ]] || die "--server, --port and --psk are install-only"
  fi
  (( PURGE == 0 )) || [[ "$COMMAND" == uninstall ]] || die "--purge requires uninstall"
  if (( ALLOW_DOWNGRADE )); then
    [[ "$COMMAND" == upgrade && -n "$EXACT" ]] || die "--allow-downgrade requires upgrade --version"
  fi
  if [[ -n "$EXACT" ]]; then
    EXACT=${EXACT#v}
    version_key "$EXACT" >/dev/null || die "Invalid version: $EXACT (example: 6.0.0rc2)"
    supported_version "$EXACT" || die "Unsupported Snell major; update the management tool"
  fi
}

# Numeric components first, then maturity, then numeric prerelease sequence.
# The fixed-width key is compared in the C locale, never by raw version spelling.
version_key() {
  local v=${1#v} major minor patch suffix seq rank
  [[ "$v" =~ ^([0-9]{1,6})\.([0-9]{1,6})\.([0-9]{1,6})((b|rc)([0-9]{1,6})?)?$ ]] || return 1
  major=$((10#${BASH_REMATCH[1]})); minor=$((10#${BASH_REMATCH[2]})); patch=$((10#${BASH_REMATCH[3]}))
  suffix=${BASH_REMATCH[5]:-}; seq=${BASH_REMATCH[6]:-1}
  case "$suffix" in b) rank=0 ;; rc) rank=1 ;; '') rank=2; seq=0 ;; esac
  printf '%06d.%06d.%06d.%d.%06d\n' "$major" "$minor" "$patch" "$rank" "$((10#$seq))"
}
version_channel() {
  case "$1" in *rc*) printf 'rc\n' ;; *b*) printf 'beta\n' ;; *) printf 'stable\n' ;; esac
}
supported_version() { [[ "$1" == 5.* || "$1" == 6.* ]]; }
binary_report_matches() {
  # Official v6 RC2 reports "v6.0.0" without the prerelease suffix. The selected
  # artifact label remains tied to its official URL/hash, not this reduced report.
  [[ "$1" == "$2" ]] && return 0
  [[ $(version_channel "$1") != stable && "$2" == "${1%%[br]*}" ]]
}
channel_allows() {
  case "$1:$(version_channel "$2")" in stable:stable|rc:stable|rc:rc|beta:*) return 0 ;; *) return 1 ;; esac
}
detect_arch() {
  case "$(uname -m)" in x86_64|amd64) ARCH=amd64 ;; aarch64|arm64) ARCH=aarch64 ;; *) die "Only amd64/aarch64 are supported" ;; esac
}

# Emit version<TAB>architecture<TAB>URL; no executable content is taken from a page.
parse_releases() {
  local url name v arch invalid=0
  while IFS= read -r url; do
    name=${url##*/}
    [[ "$name" =~ ^snell-server-v(.+)-linux-(amd64|aarch64|i386|armv7l)\.zip$ ]] || continue
    v=${BASH_REMATCH[1]}; arch=${BASH_REMATCH[2]}
    if version_key "$v" >/dev/null; then
      printf '%s\t%s\t%s\n' "$v" "$arch" "$url"
    else
      warn "Unrecognized upstream version format: $v; update the management tool"
      invalid=1
    fi
  done < <(grep -Eo 'https://dl\.nssurge\.com/snell/snell-server-v[^"<>[:space:]()]+\.zip' | LC_ALL=C sort -u)
  (( invalid == 0 ))
}
fetch_catalog() {
  local page records suffix
  for suffix in .md ''; do
    if page=$(curl -fsSL --proto '=https' --proto-redir '=https' --retry 2 --connect-timeout 10 --max-time 45 \
      -A 'snellctl/1.0' "$NOTES$suffix"); then
      if records=$(printf '%s\n' "$page" | parse_releases) && [[ -n "$records" ]]; then printf '%s\n' "$records"; return 0; fi
    fi
  done
  warn "Official release discovery failed; no cached or older release will be substituted"
  return 1
}
select_release() {
  local catalog=$1 ceiling=$2 arch=$3 v a url key best_key='' best='' result=''
  # Select the globally newest candidate before checking architecture availability.
  # Otherwise an absent ARM build could silently select an older release.
  while IFS=$'\t' read -r v a url; do
    [[ -n "$v" ]] || continue
    channel_allows "$ceiling" "$v" || continue
    key=$(version_key "$v") || continue
    if [[ -z "$best_key" || "$key" > "$best_key" ]]; then best_key=$key; best=$v; fi
  done <<<"$catalog"
  [[ -n "$best" ]] || { warn "No release found for channel $ceiling"; return 1; }
  supported_version "$best" || { warn "Latest release is $best; update the management tool for this major"; return 1; }
  while IFS=$'\t' read -r v a url; do
    if [[ "$v" == "$best" && "$a" == "$arch" ]]; then result=$url; break; fi
  done <<<"$catalog"
  [[ -n "$result" ]] || { warn "Latest $ceiling release $best has no $arch download"; return 1; }
  printf '%s\t%s\n' "$best" "$result"
}
resolve_target() {
  local selected catalog
  if [[ -n "$EXACT" ]]; then
    TARGET=$EXACT; TARGET_URL="$DOWNLOAD_BASE/snell-server-v${TARGET}-linux-${ARCH}.zip"
  else
    catalog=$(fetch_catalog) || die "Cannot determine latest release"
    selected=$(select_release "$catalog" "$TARGET_CHANNEL" "$ARCH") || die "Cannot select target"
    IFS=$'\t' read -r TARGET TARGET_URL <<<"$selected"
  fi
}

valid_port() { [[ "$1" =~ ^[0-9]{1,5}$ ]] && (( 10#$1 >= 1 && 10#$1 <= 65535 )); }
valid_server() {
  local label n
  [[ ${#1} -le 253 && "$1" != *[!A-Za-z0-9.-]* && "$1" != .* && "$1" != *. && "$1" != *..* ]] || return 1
  if [[ "$1" =~ ^[0-9.]+$ ]]; then
    [[ "$1" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]] || return 1
    local old_ifs=$IFS; IFS=.
    for n in $1; do
      if [[ ${#n} -gt 3 ]] || (( 10#$n > 255 )); then IFS=$old_ifs; return 1; fi
    done
    IFS=$old_ifs
  else
    local old_ifs=$IFS; IFS=.
    for label in $1; do
      [[ "$label" =~ ^[A-Za-z0-9]([A-Za-z0-9-]{0,61}[A-Za-z0-9])?$ ]] || { IFS=$old_ifs; return 1; }
    done
    IFS=$old_ifs
  fi
}
confirm() {
  local answer
  (( YES )) && return 0
  if (( NON_INTERACTIVE )) || [[ ! -t 0 ]]; then die "Use --yes to authorize this non-interactive operation"; fi
  read -r -p 'Continue? [y/N]: ' answer || die "No confirmation received"
  [[ "$answer" == y || "$answer" == Y ]] || die "Cancelled"
}
require_linux_root() {
  [[ $(uname -s) == Linux ]] || die "This command requires Linux"
  (( EUID == 0 )) || die "Run as root (sudo)"
  [[ -r /etc/os-release ]] || die "Cannot identify OS"
  local ID=
  # shellcheck disable=SC1091
  . /etc/os-release
  [[ "$ID" == debian || "$ID" == ubuntu ]] || die "Only Debian/Ubuntu are supported"
  if [[ ! -d /run/systemd/system ]] || ! command -v systemctl >/dev/null; then die "A running systemd system is required"; fi
}
ensure_dependencies() {
  local cmd missing=0
  for cmd in curl unzip jq file openssl flock ss sha256sum timeout runuser; do
    command -v "$cmd" >/dev/null || missing=1
  done
  [[ -r /etc/ssl/certs/ca-certificates.crt ]] || missing=1
  if (( missing )); then
    log 'Installing required OS packages…'
    apt-get update
    DEBIAN_FRONTEND=noninteractive apt-get install -y ca-certificates curl unzip jq file openssl util-linux iproute2 coreutils passwd
  fi
}
require_tools() {
  local cmd
  for cmd in "$@"; do command -v "$cmd" >/dev/null || die "Required command missing: $cmd"; done
}

secure_dir() {
  [[ -d "$1" && ! -L "$1" ]] || return 1
  [[ $(stat -c %u "$1") == 0 ]] || return 1
  local mode
  mode=$(stat -c %a "$1")
  (( (8#$mode & 0022) == 0 ))
}
regular_owned() {
  [[ -f "$1" && ! -L "$1" && $(stat -c %u "$1") == 0 ]] || return 1
  local mode
  mode=$(stat -c %a "$1")
  (( (8#$mode & 0022) == 0 ))
}
owned_base() {
  secure_dir "$BASE" && regular_owned "$BASE/.owner" && [[ $(cat "$BASE/.owner") == "$OWNER" ]]
}
managed_file() { regular_owned "$1" && grep -Fxq '# snellctl-managed-v1' "$1"; }
acquire_lock() {
  [[ ! -L "$LOCK_DIR" ]] || die "Unsafe lock directory"
  if [[ ! -e "$LOCK_DIR" ]]; then mkdir -m 0700 "$LOCK_DIR" || die "Cannot create lock directory"; fi
  secure_dir "$LOCK_DIR" || die "Unsafe lock directory ownership"
  [[ $(stat -c %a "$LOCK_DIR") == 700 && ! -L "$LOCK_DIR/lock" ]] || die "Unsafe lock permissions"
  exec 9>"$LOCK_DIR/lock"
  flock -n 9 || die "Another snellctl operation is running"
  LOCKED=1
}
check_owned_files() {
  local p
  OWNERSHIP_CHECKED=0
  owned_base || die "No snellctl-owned installation; legacy installations are never adopted"
  secure_dir "$BASE/generations" || die "Unsafe generations directory"
  for p in "$BASE/state.json" "$BASE/transaction.json"; do
    [[ ! -e "$p" && ! -L "$p" ]] || regular_owned "$p" || die "Unsafe state file: $p"
  done
  for p in "$UNIT" "$MANAGER"; do
    [[ ! -e "$p" && ! -L "$p" ]] || managed_file "$p" || die "Refusing to modify foreign file: $p"
  done
  p=$(systemctl show "$SERVICE" -p FragmentPath --value 2>/dev/null || true)
  [[ -z "$p" || "$p" == "$UNIT" ]] || die "Foreign Snell service fragment: $p"
  [[ ! -e "$UNIT.d" && ! -L "$UNIT.d" ]] || die "Remove external systemd overrides manually before managing this installation"
  if [[ -e "$BASE/account" || -L "$BASE/account" ]]; then
    regular_owned "$BASE/account" || die "Unsafe service-account record"
    [[ $(cat "$BASE/account") == "$(id -u snell):$(id -g snell)" ]] || die "Service account identity has changed"
  fi
  OWNERSHIP_CHECKED=1
  for p in "$BASE"/.stage-* "$BASE"/.json-* "$BASE"/.unit-*; do
    [[ ! -e "$p" && ! -L "$p" ]] || warn "Interrupted preparation retained at $p; inspect and remove manually"
  done
}
fresh_guard() {
  local p fragment
  if [[ -e "$BASE" || -L "$BASE" ]]; then
    check_owned_files
    [[ ! -e "$BASE/state.json" ]] || [[ $(jq -r '.current // empty' "$BASE/state.json") == '' ]] || die "Deployment data already exists; use upgrade, or explicitly uninstall --purge before reinstalling"
  else
    for p in "$UNIT" "$UNIT.d" "$MANAGER" /etc/snell /usr/local/bin/snell-server /usr/local/sbin/snell-server /usr/bin/snell-server /opt/snell /usr/local/bin/shadow-tls /etc/systemd/system/shadow-tls.service; do
      [[ ! -e "$p" && ! -L "$p" ]] || die "Existing deployment/file detected: $p. Remove it manually; migration is not supported"
    done
    fragment=$(systemctl show "$SERVICE" -p FragmentPath --value 2>/dev/null || true)
    [[ -z "$fragment" ]] || die "A foreign Snell systemd unit exists: $fragment"
    fragment=$(systemctl list-unit-files --no-legend '*snell*' 2>/dev/null || true)
    [[ -z "$fragment" ]] || die "Existing Snell unit detected; inspect systemctl list-unit-files '*snell*' and remove it manually"
    for p in /proc/[0-9]*/comm; do
      [[ -r "$p" ]] || continue
      IFS= read -r fragment <"$p" || continue
      [[ "$fragment" != snell-server ]] || die "Existing Snell process detected; stop and remove its deployment manually"
    done
    ! getent passwd snell >/dev/null || die "Existing snell account is not owned by this tool"
    ! getent group snell >/dev/null || die "Existing snell group is not owned by this tool"
  fi
}
atomic_json() {
  local path=$1 tmp
  tmp=$(mktemp "$BASE/.json-XXXXXXXX") || return 1
  if ! jq . >"$tmp"; then rm -f "$tmp"; return 1; fi
  chmod 0600 "$tmp"
  mv -fT "$tmp" "$path"
}
init_layout() {
  if [[ ! -e "$BASE" ]]; then
    mkdir -m 0755 "$BASE"
    printf '%s\n' "$OWNER" >"$BASE/.owner"
    mkdir -m 0755 "$BASE/generations"
    printf '{"current":null,"previous":null,"installed":false}\n' | atomic_json "$BASE/state.json"
  fi
  if [[ ! -e "$BASE/account" ]]; then
    if getent passwd snell >/dev/null || getent group snell >/dev/null; then die "Unowned snell account; resolve manually"; fi
    groupadd --system snell
    useradd --system --gid snell --home-dir /nonexistent --no-create-home --shell /usr/sbin/nologin snell
    printf '%s:%s\n' "$(id -u snell)" "$(id -g snell)" >"$BASE/account"
  fi
  [[ $(cat "$BASE/account") == "$(id -u snell):$(id -g snell)" ]] || die "Service account identity has changed"
  OWNERSHIP_CHECKED=1
}
valid_gen_id() { [[ "$1" =~ ^g-[A-Za-z0-9]+$ ]]; }
generation_dir() {
  valid_gen_id "$1" || return 1
  local dir="$BASE/generations/$1" entry
  secure_dir "$dir" && regular_owned "$dir/.owner" && [[ $(cat "$dir/.owner") == "$OWNER" ]] || return 1
  for entry in "$dir"/* "$dir"/.[!.]* "$dir"/..?*; do
    [[ -e "$entry" || -L "$entry" ]] || continue
    case "${entry##*/}" in
      .owner|snell-server|snell-server.conf|surge.conf|metadata.json) regular_owned "$entry" || return 1 ;;
      *) return 1 ;;
    esac
  done
  printf '%s\n' "$dir"
}
verify_generation() {
  local dir path expected actual
  dir=$(generation_dir "$1") || return 1
  for path in metadata.json snell-server snell-server.conf surge.conf; do regular_owned "$dir/$path" || return 1; done
  jq -e '.schema == 1 and (.version|type == "string") and (.settings.port|type == "number")' "$dir/metadata.json" >/dev/null || return 1
  for path in snell-server snell-server.conf surge.conf; do
    expected=$(jq -r --arg name "$path" '.hashes[$name]' "$dir/metadata.json") || return 1
    actual=$(sha256sum "$dir/$path"); actual=${actual%% *}
    [[ "$actual" == "$expected" ]] || { warn "Snapshot integrity check failed: $1/$path"; return 1; }
  done
}
current_id() { jq -er '.current | select(type == "string")' "$BASE/state.json"; }
check_current() {
  local id
  id=$(current_id) || die "No current deployment"
  verify_generation "$id" || die "Current snapshot is invalid; refusing to guess or overwrite it"
  [[ -L "$BASE/current" && $(readlink "$BASE/current") == "generations/$id" ]] || die "Current pointer disagrees with committed state"
}
activate_pointer() {
  local id=$1
  generation_dir "$id" >/dev/null || return 1
  [[ ! -e "$BASE/.next" && ! -L "$BASE/.next" ]] || rm -f "$BASE/.next" || return 1
  ln -s "generations/$id" "$BASE/.next" || return 1
  mv -fT "$BASE/.next" "$BASE/current"
}
port_busy() {
  local result
  result=$(ss -H -ltn "sport = :$1") || return 2
  [[ -n "$result" ]]
}
collect_install_settings() {
  local answer
  PORT=${PORT:-443}
  if (( NON_INTERACTIVE == 0 )) && [[ -t 0 ]]; then
    if [[ -z "$SERVER" ]]; then read -r -p 'Public IPv4 address or DNS name: ' SERVER || die "Missing server"; fi
    read -r -p "Listen port [$PORT]: " answer || die "Missing port input"; PORT=${answer:-$PORT}
    if [[ -z "$CHANNEL$EXACT" ]]; then read -r -p 'Channel [stable] (stable/rc/beta): ' CHANNEL || die "Missing channel input"; fi
  fi
  if [[ -z "$SERVER" ]] || ! valid_server "$SERVER"; then die "Provide a valid public IPv4 address or DNS name using --server"; fi
  valid_port "$PORT" || die "Invalid port"
  PORT=$((10#$PORT))
  CHANNEL=${CHANNEL:-stable}
  [[ "$CHANNEL" == stable || "$CHANNEL" == rc || "$CHANNEL" == beta ]] || die "Invalid channel"
  [[ -n "$PSK" ]] || PSK=$(openssl rand -hex 32)
  [[ "$PSK" =~ ^[A-Za-z0-9_-]{16,255}$ ]] || die "PSK must be 16–255 ASCII letters/digits/_/-"
  if port_busy "$PORT"; then die "TCP port $PORT is already occupied; no existing process was stopped"; else [[ $? == 1 ]] || die "Unable to check listening ports"; fi
  TARGET_CHANNEL=$CHANNEL
  [[ -z "$EXACT" ]] || TARGET_CHANNEL=$(version_channel "$EXACT")
}
load_settings() {
  local dir
  dir="$BASE/generations/$(current_id)"
  SERVER=$(jq -r '.settings.server' "$dir/metadata.json")
  PORT=$(jq -r '.settings.port' "$dir/metadata.json")
  PSK=$(sed -n 's/^psk = //p' "$dir/snell-server.conf")
  TARGET_CHANNEL=${CHANNEL:-$(jq -r '.channel' "$dir/metadata.json")}
}
render_server_config() {
  printf '[snell-server]\nlisten = 0.0.0.0:%s\npsk = %s\nipv6 = false\n' "$PORT" "$PSK"
}
render_surge_config() {
  printf 'Snell = snell, %s, %s, psk=%s, version=%s, reuse=true, block-quic=on\n' "$SERVER" "$PORT" "$PSK" "${TARGET%%.*}"
}

download_archive() {
  local url=$1 output=$2 effective
  effective=$(curl -fLsS --proto '=https' --proto-redir '=https' --retry 2 --connect-timeout 10 --max-time 180 \
    -o "$output" -w '%{url_effective}' "$url") || return 1
  [[ "$effective" == "$DOWNLOAD_BASE/"* ]] || { warn "Download redirected outside the official Snell directory"; return 1; }
}
verify_upstream_checksum() {
  local url=$1 archive=$2 code checksum actual effective
  # Optional official sibling sidecar. Only 404/410 means absent, not a network error.
  code=$(curl -sSL --proto '=https' --proto-redir '=https' --connect-timeout 10 --max-time 30 \
    -o "$WORK/upstream.sha256" -w '%{http_code} %{url_effective}' "$url.sha256") || return 1
  effective=${code#* }; code=${code%% *}
  [[ "$effective" == "$DOWNLOAD_BASE/"* ]] || return 1
  case "$code" in
    404|410) CHECKSUM_SOURCE=local-only; return 0 ;;
    200) ;;
    *) warn "Checksum endpoint failed (HTTP $code)"; return 1 ;;
  esac
  checksum=$(awk 'NF {print $1}' "$WORK/upstream.sha256")
  [[ "$checksum" =~ ^[A-Fa-f0-9]{64}$ ]] || { warn "Invalid official checksum sidecar"; return 1; }
  actual=$(sha256sum "$archive"); actual=${actual%% *}
  [[ "$actual" == "$(printf '%s' "$checksum" | tr A-F a-f)" ]] || { warn "Official checksum mismatch"; return 1; }
  CHECKSUM_SOURCE=official-sidecar
}
stage_generation() {
  local listing count file_desc version_output actual binary_hash config_hash surge_hash archive_hash gen
  WORK=$(mktemp -d "$BASE/.stage-XXXXXXXX")
  chmod 0750 "$WORK"; chown root:snell "$WORK"
  log "Downloading Snell $TARGET ($ARCH)…"
  download_archive "$TARGET_URL" "$WORK/release.zip" || die "Download failed; existing deployment unchanged"
  unzip -tq "$WORK/release.zip" >/dev/null || die "Corrupt ZIP; existing deployment unchanged"
  listing=$(unzip -Z1 "$WORK/release.zip") || die "Cannot inspect ZIP"
  count=$(printf '%s\n' "$listing" | awk '$0 == "snell-server" {n++} END {print n+0}')
  [[ "$count" == 1 ]] || die "ZIP must contain exactly one root-level snell-server"
  if printf '%s\n' "$listing" | grep -Eq '(^/|(^|/)\.\.(/|$)|\\)'; then die "Unsafe ZIP member path"; fi
  verify_upstream_checksum "$TARGET_URL" "$WORK/release.zip" || die "Checksum verification failed"
  # Extract only this member; archive paths, links and permissions are never installed.
  unzip -p "$WORK/release.zip" snell-server >"$WORK/snell-server" || die "Cannot extract binary"
  file_desc=$(file -b "$WORK/snell-server")
  [[ "$file_desc" == *'ELF 64-bit LSB'* ]] || die "Download is not a 64-bit Linux ELF binary"
  case "$ARCH:$file_desc" in amd64:*x86-64*|aarch64:*aarch64*) ;; *) die "Wrong binary architecture" ;; esac
  chmod 0755 "$WORK/snell-server"
  version_output=$(timeout 10 runuser -u snell -- "$WORK/snell-server" --version 2>&1) || die "Downloaded binary cannot run as snell; check OS libraries and architecture"
  actual=$(printf '%s\n' "$version_output" | grep -Eo '[0-9]+\.[0-9]+\.[0-9]+((b|rc)[0-9]*)?' | head -n 1) || die "Cannot read binary version"
  binary_report_matches "$TARGET" "$actual" || die "Binary version does not match selected release"
  [[ "$actual" == "$TARGET" ]] || log "Binary reports $actual without a prerelease suffix; artifact label $TARGET is recorded with its official URL and hash."
  render_server_config >"$WORK/snell-server.conf"
  render_surge_config >"$WORK/surge.conf"
  chmod 0640 "$WORK/snell-server.conf"; chown root:snell "$WORK/snell-server.conf"
  chmod 0600 "$WORK/surge.conf"
  binary_hash=$(sha256sum "$WORK/snell-server"); config_hash=$(sha256sum "$WORK/snell-server.conf")
  surge_hash=$(sha256sum "$WORK/surge.conf"); archive_hash=$(sha256sum "$WORK/release.zip")
  jq -n --arg version "$TARGET" --arg reported "$actual" --arg protocol "${TARGET%%.*}" --arg channel "$TARGET_CHANNEL" \
    --arg url "$TARGET_URL" --arg arch "$ARCH" --arg server "$SERVER" --argjson port "$PORT" \
    --arg binary "${binary_hash%% *}" --arg config "${config_hash%% *}" --arg surge "${surge_hash%% *}" \
    --arg archive "${archive_hash%% *}" --arg checksum "$CHECKSUM_SOURCE" --arg created "$(date -u +%FT%TZ)" \
    '{schema:1,version:$version,binary_reported_version:$reported,protocol:($protocol|tonumber),channel:$channel,url:$url,arch:$arch,created:$created,
      settings:{server:$server,port:$port},checksum:$checksum,archive_sha256:$archive,
      hashes:{"snell-server":$binary,"snell-server.conf":$config,"surge.conf":$surge}}' >"$WORK/metadata.json"
  chmod 0600 "$WORK/metadata.json"
  printf '%s\n' "$OWNER" >"$WORK/.owner"
  rm -f "$WORK/release.zip" "$WORK/upstream.sha256"
  gen=$(mktemp -d "$BASE/generations/g-XXXXXXXX"); rmdir "$gen"
  mv -T "$WORK" "$gen"; WORK=
  NEW_GEN=${gen##*/}
}
write_runtime() {
  local tmp
  tmp=$(mktemp "$BASE/.unit-XXXXXXXX")
  cat >"$tmp" <<EOF
# snellctl-managed-v1
[Unit]
Description=Snell managed by snellctl
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
User=snell
Group=snell
ExecStart=$BASE/current/snell-server -c $BASE/current/snell-server.conf
Restart=on-failure
RestartSec=2
LimitNOFILE=65536
NoNewPrivileges=true
CapabilityBoundingSet=CAP_NET_BIND_SERVICE
AmbientCapabilities=CAP_NET_BIND_SERVICE
ProtectSystem=strict
ProtectHome=true
PrivateTmp=true
RestrictAddressFamilies=AF_INET AF_INET6 AF_UNIX AF_NETLINK
UMask=0077

[Install]
WantedBy=multi-user.target
EOF
  install -m 0644 "$tmp" "$UNIT"; rm -f "$tmp"
  tmp=$(mktemp "${MANAGER}.XXXXXXXX")
  install -m 0755 "$SELF" "$tmp"
  mv -fT "$tmp" "$MANAGER"
  systemctl daemon-reload
  systemctl enable "$SERVICE" >/dev/null
}
health_check() {
  local id=$1 dir port pid executable listeners i stable_pid='' stable=0
  dir=$(generation_dir "$id") || return 1
  port=$(jq -r '.settings.port' "$dir/metadata.json") || return 1
  # Require five consecutive healthy samples of the same PID within 15 seconds.
  for ((i=0; i<15; i++)); do
    pid=$(systemctl show "$SERVICE" -p MainPID --value) || return 1
    if [[ "$pid" =~ ^[1-9][0-9]*$ ]] && systemctl is-active --quiet "$SERVICE"; then
      executable=$(readlink -f "/proc/$pid/exe" 2>/dev/null || true)
      listeners=$(ss -H -ltnp "sport = :$port") || return 1
      if [[ "$executable" == "$dir/snell-server" && "$listeners" == *"pid=$pid,"* && "$listeners" == *"0.0.0.0:$port"* ]]; then
        if [[ "$stable_pid" == "$pid" ]]; then stable=$((stable+1)); else stable_pid=$pid; stable=1; fi
        (( stable >= 5 )) && return 0
      else stable=0; fi
    else stable=0; fi
    sleep 1
  done
  return 1
}
remove_runtime() {
  if [[ -e "$UNIT" ]]; then systemctl disable --now "$SERVICE" >/dev/null 2>&1 || return 1; fi
  if [[ -e "$UNIT" || -L "$UNIT" ]]; then managed_file "$UNIT" || return 1; rm -f "$UNIT" || return 1; fi
  if [[ -e "$MANAGER" || -L "$MANAGER" ]]; then managed_file "$MANAGER" || return 1; rm -f "$MANAGER" || return 1; fi
  systemctl daemon-reload
}
recover_transaction() {
  [[ -e "$BASE/transaction.json" ]] || return 0
  local old id
  old=$(jq -ce '.old | select(type == "object" and (.installed|type == "boolean"))' "$BASE/transaction.json") || return 1
  id=$(jq -r '.current // empty' <<<"$old") || return 1
  warn 'Recovering the previous complete deployment from an unfinished transaction'
  if [[ -n "$id" ]]; then
    verify_generation "$id" || return 1
    systemctl stop "$SERVICE" || return 1
    activate_pointer "$id" || return 1
    systemctl start "$SERVICE" || return 1
    health_check "$id" || { warn 'Previous deployment also failed to start; transaction retained for diagnosis'; return 1; }
  else
    # A first-install failure has no previous deployment to restart.
    systemctl stop "$SERVICE" >/dev/null 2>&1 || true
    remove_runtime || return 1
    [[ ! -L "$BASE/current" ]] || rm -f "$BASE/current" || return 1
  fi
  printf '%s\n' "$old" | atomic_json "$BASE/state.json" || return 1
  rm -f "$BASE/transaction.json"
}
switch_generation() {
  local id=$1 old previous
  verify_generation "$id" || die "Invalid target snapshot"
  old=$(cat "$BASE/state.json")
  previous=$(jq -r '.current // empty' <<<"$old")
  jq -n --argjson old "$old" --arg target "$id" '{old:$old,target:$target}' | atomic_json "$BASE/transaction.json"
  if [[ -z "$previous" ]]; then write_runtime; else systemctl stop "$SERVICE"; fi
  activate_pointer "$id"
  if ! systemctl start "$SERVICE" || ! health_check "$id"; then
    warn 'New deployment failed local health checks; attempting rollback'
    recover_transaction || die "Automatic recovery failed; transaction retained at $BASE/transaction.json"
    die "Deployment failed; previous state restored"
  fi
  jq -n --arg current "$id" --arg previous "$previous" \
    '{current:$current,previous:(if $previous == "" then null else $previous end),installed:true}' | atomic_json "$BASE/state.json"
  # This unlink is the commit point. Until then, recovery restores the old state.
  rm -f "$BASE/transaction.json"
}
prune_generations() {
  local dir id current previous
  [[ ! -e "$BASE/transaction.json" ]] || return 0
  current=$(jq -r '.current // empty' "$BASE/state.json"); previous=$(jq -r '.previous // empty' "$BASE/state.json")
  for dir in "$BASE"/generations/g-*; do
    [[ -e "$dir" || -L "$dir" ]] || continue
    id=${dir##*/}
    [[ "$id" != "$current" && "$id" != "$previous" ]] || continue
    if generation_dir "$id" >/dev/null; then rm -rf -- "$dir"; else warn "Unowned snapshot path retained: $dir"; fi
  done
}
cleanup_exit() {
  local status=$?
  trap - EXIT INT TERM
  set +e
  if (( LOCKED && OWNERSHIP_CHECKED )) && owned_base; then
    if [[ -e "$BASE/transaction.json" ]]; then recover_transaction || warn 'Recovery incomplete; rerun snellctl before any further changes'; status=1; fi
    if [[ -n "$WORK" && "$WORK" == "$BASE"/.stage-* && -d "$WORK" && ! -L "$WORK" ]]; then rm -rf -- "$WORK"; fi
    [[ ! -e "$BASE/state.json" ]] || prune_generations
  fi
  exit "$status"
}

run_deploy() {
  local old_version old_key target_key id
  if [[ "$COMMAND" == install ]]; then
    fresh_guard
    collect_install_settings
  else
    check_owned_files
    recover_transaction || die "Cannot recover unfinished transaction"
    check_current
    [[ $(jq -r .installed "$BASE/state.json") == true ]] || die "Service was uninstalled; purge retained data before a fresh install"
    load_settings
  fi
  resolve_target
  if [[ "$COMMAND" == upgrade ]]; then
    id=$(current_id); old_version=$(jq -r .version "$BASE/generations/$id/metadata.json")
    old_key=$(version_key "$old_version"); target_key=$(version_key "$TARGET")
    [[ "$target_key" > "$old_key" || "$target_key" == "$old_key" || "$ALLOW_DOWNGRADE" == 1 ]] || die "Refusing downgrade $old_version -> $TARGET; use --version and --allow-downgrade"
    if [[ "$old_version" == "$TARGET" && "$TARGET_CHANNEL" == "$(jq -r .channel "$BASE/generations/$id/metadata.json")" ]]; then
      log "Already on $TARGET ($TARGET_CHANNEL). Nothing changed."; return 0
    fi
  fi
  log "Operation: $COMMAND | ${old_version:-none} -> $TARGET | channel: $TARGET_CHANNEL | protocol: ${TARGET%%.*}"
  log "Public endpoint: $SERVER:$PORT | Surge: version=${TARGET%%.*}, reuse=true, block-quic=on"
  [[ $(version_channel "$TARGET") == stable ]] || warn 'Prerelease: the Surge client may require a compatible update. Local health checks cannot prove protocol compatibility.'
  [[ -z "${old_version:-}" ]] || log 'Connections will briefly disconnect. PSK and endpoint are preserved.'
  confirm
  init_layout
  stage_generation
  switch_generation "$NEW_GEN"
  prune_generations
  log "Installed Snell $TARGET. Local process/listener checks passed; client connectivity is not yet verified."
  log "Allow inbound TCP $PORT in your firewall and provider security group. No firewall settings were changed."
  log 'Run sudo snellctl export to obtain the Surge configuration (contains the PSK).'
}
run_versions() {
  local catalog v a url key ceiling selected dir
  require_tools curl
  catalog=$(fetch_catalog) || die "Unable to query official versions"
  log 'Officially discoverable versions (not a complete historical archive):'
  while IFS=$'\t' read -r v a url; do
    key=$(version_key "$v") || continue
    printf '%s\t%s\t%s\t%s\n' "$key" "$v" "$a" "$(version_channel "$v")"
  done <<<"$catalog" | LC_ALL=C sort -r | cut -f2-
  for ceiling in stable rc beta; do
    if selected=$(select_release "$catalog" "$ceiling" "$ARCH"); then log "$ceiling ($ARCH): ${selected%%$'\t'*}"; else log "$ceiling ($ARCH): unavailable / management-tool update required"; fi
  done
  if [[ -d "$BASE" ]]; then
    log 'Local snapshots: run sudo snellctl status for verified deployment details.'
    if (( EUID == 0 )) && owned_base && command -v jq >/dev/null; then
      for dir in "$BASE"/generations/g-*; do
        [[ -d "$dir" ]] || continue
        if verify_generation "${dir##*/}"; then jq -r --arg id "${dir##*/}" '"\($id)\t\(.version)\t\(.channel)"' "$dir/metadata.json"; fi
      done
    fi
  fi
}
run_status() {
  local id dir previous pid executable version
  id=$(current_id) || { log 'No completed deployment.'; return 0; }
  check_current
  dir="$BASE/generations/$id"
  jq -r '"Selected: \(.version) | protocol: \(.protocol) | channel: \(.channel)\nEndpoint: \(.settings.server):\(.settings.port)\nSource: \(.url)\nChecksum: \(.checksum)"' "$dir/metadata.json"
  log "Binary version report: $(jq -r '.binary_reported_version // .version' "$dir/metadata.json")"
  log "Installed: $(jq -r .installed "$BASE/state.json")"
  previous=$(jq -r '.previous // empty' "$BASE/state.json")
  if [[ -n "$previous" ]] && verify_generation "$previous"; then log "Rollback: $(jq -r .version "$BASE/generations/$previous/metadata.json") ($previous)"; else log 'Rollback: unavailable'; fi
  pid=$(systemctl show "$SERVICE" -p MainPID --value 2>/dev/null || true)
  executable=
  [[ ! "$pid" =~ ^[1-9][0-9]*$ ]] || executable=$(readlink -f "/proc/$pid/exe" 2>/dev/null || true)
  if [[ "$executable" == "$dir/snell-server" ]]; then version=$(jq -r .version "$dir/metadata.json"); log "Running: $version | PID: $pid"; else log 'Running: stopped or does not match selected snapshot'; fi
  log "Service: $(systemctl is-active "$SERVICE" 2>/dev/null || true)"
  log 'TCP listener:'
  ss -H -ltn "sport = :$(jq -r .settings.port "$dir/metadata.json")"
  log "Diagnostics: journalctl -u $SERVICE (review before sharing)."
}
run_rollback() {
  local previous
  check_current
  [[ $(jq -r .installed "$BASE/state.json") == true ]] || die "Service is uninstalled"
  previous=$(jq -r '.previous // empty' "$BASE/state.json")
  if [[ -z "$previous" ]] || ! verify_generation "$previous"; then die "No intact previous deployment"; fi
  log "Restore complete snapshot: $(jq -r .version "$BASE/generations/$previous/metadata.json") (including saved channel and Surge configuration)"
  confirm
  switch_generation "$previous"
  log 'Previous deployment restored. Run snellctl export if the client configuration changed.'
}
run_uninstall() {
  local dir id current_uid current_gid
  log 'Remove the managed systemd service and snellctl command.'
  if (( PURGE )); then log 'Also permanently delete all managed snapshots, credentials and deployment state.'; else log "Keep complete snapshots and credentials at $BASE. Run this script with uninstall --purge to delete them later."; fi
  confirm
  remove_runtime || die "Unable to remove managed runtime"
  if (( PURGE )); then
    # Refuse recursive deletion if anything outside the owned layout appeared.
    local p name
    for p in "$BASE"/* "$BASE"/.[!.]* "$BASE"/..?*; do
      [[ -e "$p" || -L "$p" ]] || continue
      name=${p##*/}
      case "$name" in .owner|account|state.json) regular_owned "$p" || die "Unsafe retained file: $p" ;;
        current) [[ -L "$p" && $(readlink "$p") == "generations/$(current_id)" ]] || die "Unsafe current pointer" ;;
        generations) secure_dir "$p" || die "Unsafe generations directory" ;;
        *) die "Unexpected retained path: $p; inspect it manually before purge" ;;
      esac
    done
    for dir in "$BASE"/generations/* "$BASE"/generations/.[!.]* "$BASE"/generations/..?*; do
      [[ -e "$dir" || -L "$dir" ]] || continue
      generation_dir "${dir##*/}" >/dev/null || die "Unowned generation path: $dir"
    done
    current_uid=$(id -u snell); current_gid=$(id -g snell)
    [[ $(cat "$BASE/account") == "$current_uid:$current_gid" ]] || die "Account identity changed; remove manually"
    userdel snell || die "Unable to remove service account"
    if getent group snell >/dev/null; then groupdel snell || die "Unable to remove service group"; fi
    rm -rf -- "$BASE"
    log 'Managed deployment and credentials removed.'
  else
    jq '.installed = false' "$BASE/state.json" | atomic_json "$BASE/state.json"
    log 'Service removed; snapshots retained.'
  fi
}

main() {
  set -Eeuo pipefail
  export LC_ALL=C
  umask 077
  local parse_status=0
  parse_args "$@" || parse_status=$?
  [[ "$parse_status" != 2 ]] || return 0
  detect_arch
  if [[ "$COMMAND" == versions ]]; then run_versions; return; fi
  if [[ "$COMMAND" == install || "$COMMAND" == upgrade || "$COMMAND" == rollback || "$COMMAND" == uninstall ]]; then
    if (( YES == 0 )) && { (( NON_INTERACTIVE )) || [[ ! -t 0 ]]; }; then die 'Non-interactive changes require --yes'; fi
  fi
  if [[ "$COMMAND" == install && -z "$SERVER" ]] && { (( NON_INTERACTIVE )) || [[ ! -t 0 ]]; }; then die 'Non-interactive install requires --server'; fi
  require_linux_root
  if [[ "$COMMAND" == install ]]; then
    # Check ownership before package installation or any project file changes.
    fresh_guard
    ensure_dependencies
  else
    require_tools jq flock ss sha256sum
  fi
  acquire_lock
  SELF=$(readlink -f "${BASH_SOURCE[0]}")
  trap cleanup_exit EXIT
  trap 'exit 130' INT
  trap 'exit 143' TERM
  if owned_base; then
    check_owned_files
    recover_transaction || die "Unfinished transaction could not be recovered"
  fi
  case "$COMMAND" in
    install|upgrade) run_deploy ;;
    *)
      check_owned_files
      case "$COMMAND" in
        status) run_status ;;
        export) check_current; cat "$BASE/current/surge.conf" ;;
        rollback) run_rollback ;;
        uninstall) run_uninstall ;;
      esac ;;
  esac
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then main "$@"; fi
