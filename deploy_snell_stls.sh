#!/usr/bin/env bash
set -euo pipefail
IFS=$'\n\t'

SCRIPT_NAME="$(basename "$0")"

SNELL_CONF_DIR="/etc/snell"
SNELL_CONF_FILE="/etc/snell/snell-server.conf"
SNELL_BIN="/usr/local/bin/snell-server"
SHADOW_BIN="/usr/local/bin/shadow-tls"
SNELL_UNIT_FILE="/etc/systemd/system/snell-server.service"
SHADOW_UNIT_FILE="/etc/systemd/system/shadow-tls.service"
INFO_FILE="/root/snell-stls-info.txt"
SURGE_PROXY_FILE="/root/snell-surge-proxy.conf"

SURGE_SNELL_RELEASE_NOTES_URL="https://kb.nssurge.com/surge-knowledge-base/release-notes/snell"
SHADOW_TLS_RELEASE_API="https://api.github.com/repos/ihciah/shadow-tls/releases/latest"

DEFAULT_PUBLIC_PORT=443
DEFAULT_SNELL_PORT=18080

# Surge-side tuning knobs.
# Note: user requested to always emit `reuse=true` in the generated Surge line.
SURGE_TFO_VALUE="true"
SURGE_BLOCK_QUIC_VALUE="on"
SURGE_REUSE_VALUE="true"
SURGE_PROXY_NAME="Snell-v5"

declare -a SNI_CANDIDATES=(
  "www.bing.com"
  "www.microsoft.com"
)

COMMAND=""

PUBLIC_PORT="$DEFAULT_PUBLIC_PORT"
SNELL_PORT="$DEFAULT_SNELL_PORT"
SNELL_PSK=""
STLS_PASSWORD=""
STLS_SNI=""
SSH_PORT=""

NON_INTERACTIVE=0
NO_FIREWALL=0
YES=0
PURGE=0

HAS_PUBLIC_PORT=0
HAS_SNELL_PORT=0
HAS_SNELL_PSK=0
HAS_STLS_PASSWORD=0
HAS_STLS_SNI=0
HAS_SSH_PORT=0

OS_ID=""
OS_VERSION_ID=""
ARCH_LABEL=""
SNELL_ARCH_SUFFIX=""
SNELL_ARCH_REGEX=""
declare -a SHADOW_ARCH_PATTERNS=()

SNELL_VERSION=""
SNELL_DOWNLOAD_URL=""
SHADOW_TLS_VERSION=""
SHADOW_TLS_ASSET_URL=""

EXISTING_PUBLIC_PORT=""
EXISTING_SNELL_PORT=""
EXISTING_SNELL_PSK=""
EXISTING_STLS_PASSWORD=""
EXISTING_STLS_SNI=""

declare -a TMP_DIRS=()

cleanup_tmp_dirs() {
  local d
  for d in "${TMP_DIRS[@]:-}"; do
    [[ -n "$d" && -d "$d" ]] && rm -rf "$d"
  done
}
trap cleanup_tmp_dirs EXIT

new_tmp_dir() {
  local d
  d="$(mktemp -d)"
  TMP_DIRS+=("$d")
  printf '%s\n' "$d"
}

usage() {
  cat <<'EOF'
Single-port deployment script for Snell v5 + ShadowTLS v3 (Debian/Ubuntu + systemd)

Usage:
  bash deploy_snell_stls.sh install [flags]
  bash deploy_snell_stls.sh upgrade [flags]
  bash deploy_snell_stls.sh status
  bash deploy_snell_stls.sh uninstall [--purge] [--yes]

Flags:
  --public-port <port>      Public entry port for ShadowTLS (default: 443)
  --snell-port <port>       Local Snell listen port on loopback (default: 18080)
  --snell-psk <value>       Snell PSK (default: strong random)
  --stls-password <value>   ShadowTLS password (default: strong random)
  --stls-sni <domain>       ShadowTLS SNI domain (default: pick the first TLS1.3-capable candidate)
  --ssh-port <port>         SSH port kept open in firewall rules (default: auto-detect)
  --non-interactive         Non-interactive mode; use flags/defaults without prompts
  --no-firewall             Skip firewall changes; print suggested commands only
  --yes                     Skip confirmation prompt
  --purge                   uninstall only: also delete connection info and Surge snippet files
  -h, --help                Show help

Examples:
  bash deploy_snell_stls.sh install
  bash deploy_snell_stls.sh install --non-interactive --yes
  bash deploy_snell_stls.sh upgrade --public-port 443 --yes
  bash deploy_snell_stls.sh status
  bash deploy_snell_stls.sh uninstall --purge --yes
EOF
}

log() {
  printf '[INFO] %s\n' "$*"
}

warn() {
  printf '[WARN] %s\n' "$*" >&2
}

die() {
  printf '[ERROR] %s\n' "$*" >&2
  exit 1
}

require_root() {
  if [[ "${EUID}" -ne 0 ]]; then
    die "Please run as root (or via sudo)."
  fi
}

require_systemd() {
  command -v systemctl >/dev/null 2>&1 || die "systemd is required (systemctl not found)."
}

require_flag_value() {
  local flag="${1}"
  local value="${2:-}"
  if [[ -z "${value}" || "${value}" == --* ]]; then
    die "Flag ${flag} requires a value."
  fi
}

parse_args() {
  COMMAND="${1:-}"
  [[ -n "$COMMAND" ]] || {
    usage
    exit 1
  }

  case "$COMMAND" in
    install|upgrade|status|uninstall) ;;
    -h|--help|help)
      usage
      exit 0
      ;;
    *)
      die "Unknown command: $COMMAND"
      ;;
  esac
  shift || true

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --public-port)
        require_flag_value "$1" "${2:-}"
        PUBLIC_PORT="$2"
        HAS_PUBLIC_PORT=1
        shift 2
        ;;
      --snell-port)
        require_flag_value "$1" "${2:-}"
        SNELL_PORT="$2"
        HAS_SNELL_PORT=1
        shift 2
        ;;
      --snell-psk)
        require_flag_value "$1" "${2:-}"
        SNELL_PSK="$2"
        HAS_SNELL_PSK=1
        shift 2
        ;;
      --stls-password)
        require_flag_value "$1" "${2:-}"
        STLS_PASSWORD="$2"
        HAS_STLS_PASSWORD=1
        shift 2
        ;;
      --stls-sni)
        require_flag_value "$1" "${2:-}"
        STLS_SNI="$2"
        HAS_STLS_SNI=1
        shift 2
        ;;
      --ssh-port)
        require_flag_value "$1" "${2:-}"
        SSH_PORT="$2"
        HAS_SSH_PORT=1
        shift 2
        ;;
      --non-interactive)
        NON_INTERACTIVE=1
        shift
        ;;
      --no-firewall)
        NO_FIREWALL=1
        shift
        ;;
      --yes)
        YES=1
        shift
        ;;
      --purge)
        PURGE=1
        shift
        ;;
      -h|--help)
        usage
        exit 0
        ;;
      *)
        die "Unknown flag: $1"
        ;;
    esac
  done
}

ensure_supported_os() {
  [[ -r /etc/os-release ]] || die "Unable to read /etc/os-release."
  # shellcheck disable=SC1091
  . /etc/os-release

  OS_ID="${ID:-}"
  OS_VERSION_ID="${VERSION_ID:-}"

  case "$OS_ID" in
    debian|ubuntu) ;;
    *)
      die "Unsupported OS: ${OS_ID}. Only Debian/Ubuntu are supported."
      ;;
  esac

  if [[ "$OS_ID" == "debian" && "$OS_VERSION_ID" != "12" ]]; then
    warn "Best tested on Debian 12; detected Debian ${OS_VERSION_ID}."
  fi
  if [[ "$OS_ID" == "ubuntu" && "$OS_VERSION_ID" != "22.04" ]]; then
    warn "Best tested on Ubuntu 22.04; detected Ubuntu ${OS_VERSION_ID}."
  fi
}

detect_arch() {
  local machine
  machine="$(uname -m)"
  case "$machine" in
    x86_64|amd64)
      ARCH_LABEL="amd64"
      SNELL_ARCH_SUFFIX="amd64"
      SNELL_ARCH_REGEX="(amd64|x86_64)"
      SHADOW_ARCH_PATTERNS=(
        "x86_64-unknown-linux-musl"
        "x86_64-unknown-linux-gnu"
        "linux-x86_64"
        "amd64"
      )
      ;;
    aarch64|arm64)
      ARCH_LABEL="arm64"
      SNELL_ARCH_SUFFIX="aarch64"
      SNELL_ARCH_REGEX="(aarch64|arm64)"
      SHADOW_ARCH_PATTERNS=(
        "aarch64-unknown-linux-musl"
        "aarch64-unknown-linux-gnu"
        "linux-aarch64"
        "arm64"
      )
      ;;
    *)
      die "Unsupported architecture: ${machine}. Only amd64/arm64 are supported."
      ;;
  esac
}

is_valid_port() {
  local p="$1"
  [[ "$p" =~ ^[0-9]+$ ]] || return 1
  (( p >= 1 && p <= 65535 ))
}

validate_hostname() {
  local h="$1"
  [[ "$h" =~ ^([A-Za-z0-9]([A-Za-z0-9-]{0,61}[A-Za-z0-9])?\.)+[A-Za-z0-9-]{2,63}$ ]] || return 1
}

validate_runtime_values() {
  is_valid_port "$PUBLIC_PORT" || die "Invalid --public-port: $PUBLIC_PORT"
  is_valid_port "$SNELL_PORT" || die "Invalid --snell-port: $SNELL_PORT"
  is_valid_port "$SSH_PORT" || die "Invalid --ssh-port: $SSH_PORT"

  if [[ "$PUBLIC_PORT" == "$SNELL_PORT" ]]; then
    die "--public-port and --snell-port must not be the same."
  fi

  [[ -n "$SNELL_PSK" ]] || die "Snell PSK must not be empty."
  [[ -n "$STLS_PASSWORD" ]] || die "ShadowTLS password must not be empty."
  [[ -n "$STLS_SNI" ]] || die "ShadowTLS SNI must not be empty."

  [[ "$SNELL_PSK" =~ [[:space:]] ]] && die "Snell PSK must not contain spaces."
  [[ "$STLS_PASSWORD" =~ [[:space:]] ]] && die "ShadowTLS password must not contain spaces."
  validate_hostname "$STLS_SNI" || die "Invalid SNI domain: $STLS_SNI"
}

ensure_dependencies() {
  local -a pkgs=()

  command -v curl >/dev/null 2>&1 || pkgs+=("curl")
  command -v unzip >/dev/null 2>&1 || pkgs+=("unzip")
  command -v openssl >/dev/null 2>&1 || pkgs+=("openssl")
  command -v jq >/dev/null 2>&1 || pkgs+=("jq")
  command -v tar >/dev/null 2>&1 || pkgs+=("tar")
  command -v ss >/dev/null 2>&1 || pkgs+=("iproute2")

  if (( ${#pkgs[@]} > 0 )); then
    log "Installing missing dependencies: ${pkgs[*]}"
    command -v apt-get >/dev/null 2>&1 || die "apt-get is required on Debian/Ubuntu."
    DEBIAN_FRONTEND=noninteractive apt-get update -y
    DEBIAN_FRONTEND=noninteractive apt-get install -y ca-certificates "${pkgs[@]}"
  fi
}

port_is_in_use() {
  local port="$1"
  if ! command -v ss >/dev/null 2>&1; then
    return 1
  fi
  ss -lnt 2>/dev/null | awk '{print $4}' | grep -Eq "(^|:)$port$"
}

detect_ssh_port() {
  local detected=""

  if [[ -n "$SSH_PORT" ]]; then
    return
  fi

  if [[ -n "${SSH_CONNECTION:-}" ]]; then
    detected="$(awk '{print $4}' <<<"${SSH_CONNECTION}" 2>/dev/null || true)"
  fi

  if [[ -z "$detected" && -r /etc/ssh/sshd_config ]]; then
    detected="$(awk '/^[[:space:]]*Port[[:space:]]+[0-9]+/{print $2; exit}' /etc/ssh/sshd_config || true)"
  fi

  if [[ -z "$detected" ]]; then
    detected="22"
  fi

  SSH_PORT="$detected"
}

generate_secret() {
  local bytes="${1:-24}"
  openssl rand -hex "$bytes"
}

prompt_with_default() {
  local prompt="$1"
  local default_value="$2"
  local answer=""
  read -r -p "${prompt} [${default_value}]: " answer || true
  if [[ -n "$answer" ]]; then
    printf '%s\n' "$answer"
  else
    printf '%s\n' "$default_value"
  fi
}

prompt_optional() {
  local prompt="$1"
  local answer=""
  read -r -p "${prompt}: " answer || true
  printf '%s\n' "$answer"
}

collect_interactive_values() {
  local mode="$1"

  (( NON_INTERACTIVE == 1 )) && return

  if (( HAS_PUBLIC_PORT == 0 )); then
    PUBLIC_PORT="$(prompt_with_default "Public port (ShadowTLS)" "$PUBLIC_PORT")"
  fi
  if (( HAS_SNELL_PORT == 0 )); then
    SNELL_PORT="$(prompt_with_default "Snell local port (loopback)" "$SNELL_PORT")"
  fi
  if (( HAS_SSH_PORT == 0 )); then
    SSH_PORT="$(prompt_with_default "SSH port (kept open by firewall)" "$SSH_PORT")"
  fi

  if [[ "$mode" == "install" ]]; then
    if (( HAS_SNELL_PSK == 0 )); then
      local maybe_psk
      maybe_psk="$(prompt_optional "Snell PSK (leave empty to auto-generate)")"
      [[ -n "$maybe_psk" ]] && SNELL_PSK="$maybe_psk"
    fi
    if (( HAS_STLS_PASSWORD == 0 )); then
      local maybe_stls_password
      maybe_stls_password="$(prompt_optional "ShadowTLS password (leave empty to auto-generate)")"
      [[ -n "$maybe_stls_password" ]] && STLS_PASSWORD="$maybe_stls_password"
    fi
    if (( HAS_STLS_SNI == 0 )); then
      local maybe_sni
      maybe_sni="$(prompt_optional "ShadowTLS SNI domain (leave empty to auto-pick)")"
      [[ -n "$maybe_sni" ]] && STLS_SNI="$maybe_sni"
    fi
  else
    if (( HAS_SNELL_PSK == 0 )); then
      local maybe_psk_upgrade
      maybe_psk_upgrade="$(prompt_optional "Snell PSK (leave empty to keep existing / auto-generate)")"
      [[ -n "$maybe_psk_upgrade" ]] && SNELL_PSK="$maybe_psk_upgrade"
    fi
    if (( HAS_STLS_PASSWORD == 0 )); then
      local maybe_stls_password_upgrade
      maybe_stls_password_upgrade="$(prompt_optional "ShadowTLS password (leave empty to keep existing / auto-generate)")"
      [[ -n "$maybe_stls_password_upgrade" ]] && STLS_PASSWORD="$maybe_stls_password_upgrade"
    fi
    if (( HAS_STLS_SNI == 0 )); then
      local maybe_sni_upgrade
      maybe_sni_upgrade="$(prompt_optional "ShadowTLS SNI domain (leave empty to keep existing / auto-pick)")"
      [[ -n "$maybe_sni_upgrade" ]] && STLS_SNI="$maybe_sni_upgrade"
    fi
  fi
}

confirm_or_abort() {
  local mode="$1"
  (( YES == 1 || NON_INTERACTIVE == 1 )) && return

  cat <<EOF

About to run: ${mode}. Effective parameters:
  public_port: ${PUBLIC_PORT}
  snell_port : ${SNELL_PORT}
  ssh_port   : ${SSH_PORT}
  stls_sni   : ${STLS_SNI:-"(auto)"}
  firewall   : $([[ "$NO_FIREWALL" -eq 1 ]] && echo "skip" || echo "auto")
EOF

  local answer=""
  read -r -p "Continue? [y/N]: " answer || true
  if [[ ! "$answer" =~ ^[Yy]([Ee][Ss])?$ ]]; then
    die "Cancelled."
  fi
}

curl_fetch() {
  local url="$1"
  # Some sites return different content (or bot pages) without a UA.
  curl -fsSL --retry 3 --retry-delay 1 --connect-timeout 10 --max-time 120 \
    -A "Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36" \
    -H "Accept: text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8" \
    "$url"
}

download_file() {
  local url="$1"
  local out="$2"
  curl -fL --retry 3 --retry-delay 1 --connect-timeout 10 --max-time 300 -o "$out" "$url"
}

resolve_latest_snell_release() {
  local page links_raw
  local -a links=()
  local -a versions=()
  local version
  local dump_file="/tmp/snell_release_notes_last.html"

  page="$(curl_fetch "$SURGE_SNELL_RELEASE_NOTES_URL")" || die "Failed to fetch Surge Snell release notes."
  # Extract all possible dl.nssurge.com zip links that look like Snell server Linux builds.
  # The page format may change, so keep matching permissive but still scoped.
  links_raw="$(printf '%s' "$page" | grep -Eoi 'https://dl\.nssurge\.com/[^"<> ]+\.zip' || true)"
  mapfile -t links < <(
    printf '%s\n' "$links_raw" \
      | grep -Ei 'snell.*server|snell-server|snell.*linux' \
      | grep -Ei "linux-${SNELL_ARCH_SUFFIX}|linux-${SNELL_ARCH_REGEX}" \
      | sed '/^$/d' \
      | sort -u
  )

  if (( ${#links[@]} == 0 )); then
    printf '%s' "$page" >"$dump_file" 2>/dev/null || true
    if grep -qiE 'attention required|cloudflare|captcha|cf-ray' <<<"$page"; then
      die "No Snell Linux download link parsed from release notes (possible anti-bot/captcha page). Saved raw page to ${dump_file}"
    fi
    die "No Snell Linux download link found in release notes. Saved raw page to ${dump_file}"
  fi

  mapfile -t versions < <(
    printf '%s\n' "${links[@]}" \
      | grep -Eio 'v[0-9]+\.[0-9]+\.[0-9]+' \
      | sed -E 's/^v//I' \
      | awk -F. '$1 >= 5 { print $0 }' \
      | sort -V -u
  )

  (( ${#versions[@]} > 0 )) || die "No Snell v5+ version found."
  version="$(printf '%s\n' "${versions[@]}" | tail -n1)"
  SNELL_VERSION="$version"

  # Prefer exact arch suffix match, but allow x86_64/arm64 variants.
  SNELL_DOWNLOAD_URL="$(printf '%s\n' "${links[@]}" | grep -Ei "v${SNELL_VERSION}.*linux-(${SNELL_ARCH_SUFFIX}|${SNELL_ARCH_REGEX}).*\.zip" | head -n1 || true)"
  [[ -n "$SNELL_DOWNLOAD_URL" ]] || die "Unable to locate Snell download URL for arch ${SNELL_ARCH_SUFFIX}."
}

resolve_latest_shadow_tls_release() {
  local api_json
  local pattern
  local candidate

  api_json="$(curl_fetch "$SHADOW_TLS_RELEASE_API")" || die "Failed to fetch ShadowTLS latest release."
  SHADOW_TLS_VERSION="$(jq -r '.tag_name // empty' <<<"$api_json")"
  [[ -n "$SHADOW_TLS_VERSION" ]] || die "Failed to parse ShadowTLS version."

  SHADOW_TLS_ASSET_URL=""
  for pattern in "${SHADOW_ARCH_PATTERNS[@]}"; do
    candidate="$(jq -r --arg p "$pattern" '
      .assets[]
      | select((.name | test($p; "i")) and (.name | test("sha256|checksum|sig"; "i") | not))
      | .browser_download_url
    ' <<<"$api_json" | head -n1)"
    if [[ -n "$candidate" && "$candidate" != "null" ]]; then
      SHADOW_TLS_ASSET_URL="$candidate"
      break
    fi
  done

  [[ -n "$SHADOW_TLS_ASSET_URL" ]] || die "No ShadowTLS release asset found for ${ARCH_LABEL}."
}

install_snell_binary() {
  local tmp_dir zip_file extracted_bin
  tmp_dir="$(new_tmp_dir)"
  zip_file="${tmp_dir}/snell.zip"

  log "Downloading Snell v${SNELL_VERSION} (${ARCH_LABEL})..."
  download_file "$SNELL_DOWNLOAD_URL" "$zip_file"
  unzip -qo "$zip_file" -d "$tmp_dir"

  extracted_bin="$(find "$tmp_dir" -maxdepth 4 -type f -name "snell-server" | head -n1 || true)"
  [[ -n "$extracted_bin" ]] || die "snell-server binary not found after extraction."

  install -m 0755 "$extracted_bin" "$SNELL_BIN"
}

install_shadow_tls_binary() {
  local tmp_dir asset_name asset_path extracted_bin
  tmp_dir="$(new_tmp_dir)"
  asset_name="${SHADOW_TLS_ASSET_URL##*/}"
  asset_path="${tmp_dir}/${asset_name}"

  log "Downloading ShadowTLS ${SHADOW_TLS_VERSION} (${ARCH_LABEL})..."
  download_file "$SHADOW_TLS_ASSET_URL" "$asset_path"

  extracted_bin=""
  case "$asset_name" in
    *.tar.gz|*.tgz)
      tar -xzf "$asset_path" -C "$tmp_dir"
      ;;
    *.tar.xz)
      tar -xJf "$asset_path" -C "$tmp_dir"
      ;;
    *.zip)
      unzip -qo "$asset_path" -d "$tmp_dir"
      ;;
    *.gz)
      gunzip -c "$asset_path" > "${tmp_dir}/shadow-tls"
      ;;
    *)
      ;;
  esac

  if [[ -f "${tmp_dir}/shadow-tls" ]]; then
    extracted_bin="${tmp_dir}/shadow-tls"
  fi

  if [[ -z "$extracted_bin" ]]; then
    extracted_bin="$(find "$tmp_dir" -maxdepth 4 -type f \( -name "shadow-tls" -o -name "shadow-tls-*" \) ! -name "*.sha256*" ! -name "*.sig" | head -n1 || true)"
  fi

  if [[ -z "$extracted_bin" ]]; then
    extracted_bin="$asset_path"
  fi

  [[ -f "$extracted_bin" ]] || die "ShadowTLS binary not found in downloaded asset."
  chmod +x "$extracted_bin"
  install -m 0755 "$extracted_bin" "$SHADOW_BIN"

  if ! "$SHADOW_BIN" --help 2>&1 | grep -q -- '--v3'; then
    die "Installed ShadowTLS binary does not support --v3."
  fi
}

test_tls13_sni() {
  local domain="$1"
  local target="$domain"
  local output

  # Prefer IPv4 to avoid false negatives on hosts without working IPv6 route.
  if command -v getent >/dev/null 2>&1; then
    local ip4
    ip4="$(getent ahostsv4 "$domain" 2>/dev/null | awk '{print $1; exit}' || true)"
    if [[ "$ip4" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
      target="$ip4"
    fi
  fi

  if command -v timeout >/dev/null 2>&1; then
    output="$(timeout 12 openssl s_client -connect "${target}:443" -servername "${domain}" -tls1_3 < /dev/null 2>&1 || true)"
  else
    output="$(openssl s_client -connect "${target}:443" -servername "${domain}" -tls1_3 < /dev/null 2>&1 || true)"
  fi

  # Different OpenSSL versions print different summary lines.
  grep -Eq 'CONNECTED\\(' <<<"$output" || return 1
  grep -Eq 'Protocol[[:space:]]*:[[:space:]]*TLSv1\\.3|New,[[:space:]]*TLSv1\\.3|TLSv1\\.3[[:space:]]*,[[:space:]]*Cipher' <<<"$output"
}

choose_auto_sni() {
  local d

  log "Picking ShadowTLS SNI from TLS1.3-capable candidates (first match wins)..."
  for d in "${SNI_CANDIDATES[@]}"; do
    if test_tls13_sni "$d"; then
      STLS_SNI="$d"
      return
    fi
  done

  warn "No candidate passed TLS1.3 probe; falling back to gateway.icloud.com."
  STLS_SNI="gateway.icloud.com"
}

validate_or_refresh_sni() {
  if [[ -z "$STLS_SNI" ]]; then
    choose_auto_sni
    return
  fi

  if test_tls13_sni "$STLS_SNI"; then
    return
  fi

  if (( HAS_STLS_SNI == 1 )); then
    die "Provided SNI '${STLS_SNI}' did not pass TLS1.3 probe."
  fi

  warn "Current SNI '${STLS_SNI}' did not pass TLS1.3 probe; switching automatically."
  choose_auto_sni
}

write_snell_config() {
  mkdir -p "$SNELL_CONF_DIR"
  cat >"$SNELL_CONF_FILE" <<EOF
[snell-server]
listen = 127.0.0.1:${SNELL_PORT}
psk = ${SNELL_PSK}
ipv6 = false
EOF
  chmod 600 "$SNELL_CONF_FILE"
}

write_systemd_units() {
  cat >"$SNELL_UNIT_FILE" <<EOF
[Unit]
Description=Snell Server
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
ExecStart=${SNELL_BIN} -c ${SNELL_CONF_FILE}
Restart=always
RestartSec=2
LimitNOFILE=1048576
NoNewPrivileges=true

[Install]
WantedBy=multi-user.target
EOF

  cat >"$SHADOW_UNIT_FILE" <<EOF
[Unit]
Description=ShadowTLS v3 Wrapper for Snell
After=network-online.target snell-server.service
Wants=network-online.target
Requires=snell-server.service

[Service]
Type=simple
ExecStart=${SHADOW_BIN} --v3 server --listen 0.0.0.0:${PUBLIC_PORT} --server 127.0.0.1:${SNELL_PORT} --tls ${STLS_SNI} --password ${STLS_PASSWORD}
Restart=always
RestartSec=2
LimitNOFILE=1048576
NoNewPrivileges=true

[Install]
WantedBy=multi-user.target
EOF
}

restart_services() {
  systemctl daemon-reload
  systemctl enable snell-server.service shadow-tls.service >/dev/null

  if ! systemctl restart snell-server.service; then
    journalctl -u snell-server.service -n 40 --no-pager || true
    die "Failed to start snell-server.service."
  fi

  if ! systemctl restart shadow-tls.service; then
    journalctl -u shadow-tls.service -n 40 --no-pager || true
    die "Failed to start shadow-tls.service."
  fi

  systemctl is-active --quiet snell-server.service || die "snell-server.service is not active."
  systemctl is-active --quiet shadow-tls.service || die "shadow-tls.service is not active."
}

print_firewall_suggestions() {
  cat <<EOF
Suggested firewall commands:
  ufw allow ${SSH_PORT}/tcp
  ufw allow ${PUBLIC_PORT}/tcp

Or using firewalld:
  firewall-cmd --permanent --add-port=${SSH_PORT}/tcp
  firewall-cmd --permanent --add-port=${PUBLIC_PORT}/tcp
  firewall-cmd --reload

Or using iptables:
  iptables -I INPUT -p tcp --dport ${SSH_PORT} -j ACCEPT
  iptables -I INPUT -p tcp --dport ${PUBLIC_PORT} -j ACCEPT
EOF
}

configure_firewall() {
  if (( NO_FIREWALL == 1 )); then
    warn "Skipped firewall changes (--no-firewall)."
    print_firewall_suggestions
    return
  fi

  if command -v ufw >/dev/null 2>&1; then
    log "Applying firewall rules via ufw (SSH first, then public port)."
    ufw allow "${SSH_PORT}/tcp" >/dev/null || true
    ufw allow "${PUBLIC_PORT}/tcp" >/dev/null || true
    return
  fi

  if command -v firewall-cmd >/dev/null 2>&1 && systemctl is-active --quiet firewalld; then
    log "Applying firewall rules via firewalld (SSH first, then public port)."
    firewall-cmd --permanent --add-port="${SSH_PORT}/tcp"
    firewall-cmd --permanent --add-port="${PUBLIC_PORT}/tcp"
    firewall-cmd --reload
    return
  fi

  if command -v iptables >/dev/null 2>&1; then
    log "Applying firewall rules via iptables (SSH first, then public port)."
    iptables -C INPUT -p tcp --dport "$SSH_PORT" -j ACCEPT 2>/dev/null || iptables -I INPUT -p tcp --dport "$SSH_PORT" -j ACCEPT
    iptables -C INPUT -p tcp --dport "$PUBLIC_PORT" -j ACCEPT 2>/dev/null || iptables -I INPUT -p tcp --dport "$PUBLIC_PORT" -j ACCEPT

    if command -v netfilter-persistent >/dev/null 2>&1; then
      netfilter-persistent save >/dev/null || true
    else
      warn "iptables rules applied, but may not persist after reboot (netfilter-persistent not found)."
    fi
    return
  fi

  warn "No supported firewall manager found; please open ports manually."
  print_firewall_suggestions
}

detect_public_ip() {
  local -a urls=(
    "https://api.ipify.org"
    "https://ifconfig.me/ip"
    "https://ipv4.icanhazip.com"
  )
  local u ip
  for u in "${urls[@]}"; do
    ip="$(curl -4fsSL --connect-timeout 6 --max-time 8 "$u" 2>/dev/null | tr -d '\r\n' || true)"
    if [[ "$ip" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
      printf '%s\n' "$ip"
      return 0
    fi
  done
  printf '%s\n' "REPLACE_WITH_SERVER_IP"
}

write_info_file() {
  local public_ip="$1"
  local surge_line
  surge_line="snell, ${public_ip}, ${PUBLIC_PORT}, psk=${SNELL_PSK}, version=5, reuse=${SURGE_REUSE_VALUE}, shadow-tls-password=${STLS_PASSWORD}, shadow-tls-sni=${STLS_SNI}, shadow-tls-version=3, tfo=${SURGE_TFO_VALUE}, block-quic=${SURGE_BLOCK_QUIC_VALUE}"
  cat >"$INFO_FILE" <<EOF
Snell + ShadowTLS Deployment Info
=======================================
Generated at: $(date -u '+%Y-%m-%d %H:%M:%S UTC')
OS: ${OS_ID} ${OS_VERSION_ID}
Arch: ${ARCH_LABEL}
Snell version: ${SNELL_VERSION}
ShadowTLS version: ${SHADOW_TLS_VERSION}

Server public IP: ${public_ip}
Public port: ${PUBLIC_PORT}
Snell local port: ${SNELL_PORT}
Snell PSK: ${SNELL_PSK}
ShadowTLS password: ${STLS_PASSWORD}
ShadowTLS SNI: ${STLS_SNI}
ShadowTLS version: 3

Surge proxy line:
${surge_line}

Surge [Proxy] example:
[Proxy]
${SURGE_PROXY_NAME} = ${surge_line}

Surge snippet file (copy-paste friendly):
${SURGE_PROXY_FILE}
EOF
  chmod 600 "$INFO_FILE"
}

write_surge_proxy_file() {
  local public_ip="$1"
  local surge_line
  surge_line="snell, ${public_ip}, ${PUBLIC_PORT}, psk=${SNELL_PSK}, version=5, reuse=${SURGE_REUSE_VALUE}, shadow-tls-password=${STLS_PASSWORD}, shadow-tls-sni=${STLS_SNI}, shadow-tls-version=3, tfo=${SURGE_TFO_VALUE}, block-quic=${SURGE_BLOCK_QUIC_VALUE}"
  cat >"$SURGE_PROXY_FILE" <<EOF
# Snell + ShadowTLS for Surge
# Generated at: $(date -u '+%Y-%m-%d %H:%M:%S UTC')
# Notes: copy either format below into Surge

# Recommended one-liner (includes proxy name; put it under Surge [Proxy])
${SURGE_PROXY_NAME} = ${surge_line}

# Full [Proxy] block
[Proxy]
${SURGE_PROXY_NAME} = ${surge_line}
EOF
  chmod 600 "$SURGE_PROXY_FILE"
}

print_summary() {
  local mode="$1"
  local public_ip="$2"
  local surge_line
  surge_line="snell, ${public_ip}, ${PUBLIC_PORT}, psk=${SNELL_PSK}, version=5, reuse=${SURGE_REUSE_VALUE}, shadow-tls-password=${STLS_PASSWORD}, shadow-tls-sni=${STLS_SNI}, shadow-tls-version=3, tfo=${SURGE_TFO_VALUE}, block-quic=${SURGE_BLOCK_QUIC_VALUE}"
  cat <<EOF

${mode^} completed.
----------------------------------------
Snell version      : ${SNELL_VERSION}
ShadowTLS version  : ${SHADOW_TLS_VERSION}
Public entry       : ${public_ip}:${PUBLIC_PORT}
Snell loopback     : 127.0.0.1:${SNELL_PORT}
ShadowTLS SNI      : ${STLS_SNI}
Info file          : ${INFO_FILE}
Surge snippet file : ${SURGE_PROXY_FILE}

Surge [Proxy] line (includes proxy name):
${SURGE_PROXY_NAME} = ${surge_line}

Or view the full snippet file:
  cat ${SURGE_PROXY_FILE}
EOF
}

load_existing_values() {
  local listen_value exec_line

  if [[ -f "$SNELL_CONF_FILE" ]]; then
    listen_value="$(awk -F= '/^[[:space:]]*listen[[:space:]]*=/{gsub(/[[:space:]]/,"",$2); print $2; exit}' "$SNELL_CONF_FILE" || true)"
    EXISTING_SNELL_PORT="${listen_value##*:}"
    EXISTING_SNELL_PSK="$(awk -F= '/^[[:space:]]*psk[[:space:]]*=/{sub(/^[[:space:]]*/,"",$2); sub(/[[:space:]]*$/,"",$2); print $2; exit}' "$SNELL_CONF_FILE" || true)"
  fi

  if [[ -f "$SHADOW_UNIT_FILE" ]]; then
    exec_line="$(awk -F= '/^ExecStart=/{print $2; exit}' "$SHADOW_UNIT_FILE" || true)"
    if [[ "$exec_line" =~ --listen[[:space:]]+[^:]+:([0-9]+) ]]; then
      EXISTING_PUBLIC_PORT="${BASH_REMATCH[1]}"
    fi
    if [[ "$exec_line" =~ --password[[:space:]]+([^[:space:]]+) ]]; then
      EXISTING_STLS_PASSWORD="${BASH_REMATCH[1]}"
    fi
    if [[ "$exec_line" =~ --tls[[:space:]]+([^[:space:]]+) ]]; then
      EXISTING_STLS_SNI="${BASH_REMATCH[1]}"
    fi
  fi
}

prepare_defaults_for_install() {
  if (( HAS_PUBLIC_PORT == 0 )); then
    PUBLIC_PORT="$DEFAULT_PUBLIC_PORT"
  fi
  if (( HAS_SNELL_PORT == 0 )); then
    SNELL_PORT="$DEFAULT_SNELL_PORT"
  fi
}

prepare_defaults_for_upgrade() {
  [[ -f "$SNELL_CONF_FILE" || -f "$SHADOW_UNIT_FILE" ]] || die "No existing installation detected. Please run install first."
  load_existing_values

  if (( HAS_PUBLIC_PORT == 0 )) && [[ -n "$EXISTING_PUBLIC_PORT" ]]; then
    PUBLIC_PORT="$EXISTING_PUBLIC_PORT"
  fi
  if (( HAS_SNELL_PORT == 0 )) && [[ -n "$EXISTING_SNELL_PORT" ]]; then
    SNELL_PORT="$EXISTING_SNELL_PORT"
  fi
  if (( HAS_SNELL_PSK == 0 )) && [[ -n "$EXISTING_SNELL_PSK" ]]; then
    SNELL_PSK="$EXISTING_SNELL_PSK"
  fi
  if (( HAS_STLS_PASSWORD == 0 )) && [[ -n "$EXISTING_STLS_PASSWORD" ]]; then
    STLS_PASSWORD="$EXISTING_STLS_PASSWORD"
  fi
  if (( HAS_STLS_SNI == 0 )) && [[ -n "$EXISTING_STLS_SNI" ]]; then
    STLS_SNI="$EXISTING_STLS_SNI"
  fi
}

finalize_runtime_values() {
  detect_ssh_port

  [[ -n "$SNELL_PSK" ]] || SNELL_PSK="$(generate_secret 24)"
  [[ -n "$STLS_PASSWORD" ]] || STLS_PASSWORD="$(generate_secret 24)"

  validate_or_refresh_sni
  validate_runtime_values
}

run_install_or_upgrade() {
  local mode="$1"
  local public_ip

  require_root
  ensure_supported_os
  detect_arch
  require_systemd
  ensure_dependencies

  if [[ "$mode" == "install" ]]; then
    prepare_defaults_for_install
  else
    prepare_defaults_for_upgrade
  fi

  if [[ -z "$SSH_PORT" ]]; then
    detect_ssh_port
  fi

  collect_interactive_values "$mode"
  finalize_runtime_values
  confirm_or_abort "$mode"

  resolve_latest_snell_release
  resolve_latest_shadow_tls_release
  install_snell_binary
  install_shadow_tls_binary
  write_snell_config
  write_systemd_units
  configure_firewall
  restart_services

  public_ip="$(detect_public_ip)"
  write_info_file "$public_ip"
  write_surge_proxy_file "$public_ip"
  print_summary "$mode" "$public_ip"
}

run_status() {
  local public_ip

  ensure_supported_os
  require_systemd
  load_existing_values
  detect_ssh_port
  public_ip="$(detect_public_ip)"

  cat <<EOF
Status
=================
OS: ${OS_ID} ${OS_VERSION_ID}
Public IP (best-effort): ${public_ip}

Files:
  ${SNELL_BIN}        : $([[ -x "$SNELL_BIN" ]] && echo "present" || echo "missing")
  ${SHADOW_BIN}       : $([[ -x "$SHADOW_BIN" ]] && echo "present" || echo "missing")
  ${SNELL_CONF_FILE}  : $([[ -f "$SNELL_CONF_FILE" ]] && echo "present" || echo "missing")
  ${SNELL_UNIT_FILE}  : $([[ -f "$SNELL_UNIT_FILE" ]] && echo "present" || echo "missing")
  ${SHADOW_UNIT_FILE} : $([[ -f "$SHADOW_UNIT_FILE" ]] && echo "present" || echo "missing")
  ${INFO_FILE}        : $([[ -f "$INFO_FILE" ]] && echo "present" || echo "missing")
  ${SURGE_PROXY_FILE} : $([[ -f "$SURGE_PROXY_FILE" ]] && echo "present" || echo "missing")

Parsed config:
  public_port : ${EXISTING_PUBLIC_PORT:-unknown}
  snell_port  : ${EXISTING_SNELL_PORT:-unknown}
  stls_sni    : ${EXISTING_STLS_SNI:-unknown}
  ssh_port    : ${SSH_PORT}
EOF

  echo
  echo "Service status:"
  systemctl --no-pager --full status snell-server.service shadow-tls.service -n 0 || true

  echo
  echo "Listening TCP ports (filtered):"
  if command -v ss >/dev/null 2>&1; then
    ss -lntp 2>/dev/null | grep -E "(:${EXISTING_PUBLIC_PORT:-0}|:${EXISTING_SNELL_PORT:-0})\b" || true
  else
    warn "ss command not found."
  fi

  echo
  echo "Recent logs:"
  journalctl -u snell-server.service -u shadow-tls.service -n 20 --no-pager || true
}

run_uninstall() {
  require_root
  require_systemd

  if (( YES == 0 && NON_INTERACTIVE == 0 )); then
    local answer=""
    read -r -p "This will remove Snell/ShadowTLS services and binaries. Continue? [y/N]: " answer || true
    [[ "$answer" =~ ^[Yy]([Ee][Ss])?$ ]] || die "Cancelled."
  fi

  systemctl disable --now shadow-tls.service snell-server.service >/dev/null 2>&1 || true
  rm -f "$SHADOW_UNIT_FILE" "$SNELL_UNIT_FILE"
  rm -f "$SHADOW_BIN" "$SNELL_BIN"
  rm -rf "$SNELL_CONF_DIR"
  systemctl daemon-reload || true

  if (( PURGE == 1 )); then
    rm -f "$INFO_FILE"
    rm -f "$SURGE_PROXY_FILE"
  fi

  log "Uninstall completed."
  if (( PURGE == 0 )); then
    log "Connection info kept at ${INFO_FILE} and ${SURGE_PROXY_FILE}. Use --purge to delete them too."
  fi
}

main() {
  parse_args "$@"

  case "$COMMAND" in
    install)
      run_install_or_upgrade "install"
      ;;
    upgrade)
      run_install_or_upgrade "upgrade"
      ;;
    status)
      run_status
      ;;
    uninstall)
      run_uninstall
      ;;
    *)
      die "Unhandled command: $COMMAND"
      ;;
  esac
}

main "$@"
