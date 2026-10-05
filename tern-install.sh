#!/bin/sh
# Install Tern's computer tools into ~/.tern, with no sudo: `tern` (the shell server and the connector in one program,
# run as `tern-server` and `tern-connector` through two links to it) and the tern-cli command-line tool.
#
#   curl -fsSL https://github.com/asaasinventuresllc/Tern/releases/download/v0.0.1/tern-install.sh | sh
#   curl -fsSL …/tern-install.sh | sh -s -- --connector --allow <your phone's Tern key>
#
# Options:
#   --connector            also run the connector as a login-user service, so your phone can reach this computer
#                          from anywhere (it connects to Tern Relay, which introduces your phone and this computer)
#   --allow HEX            let this phone (its 64-hex Tern key) open terminal sessions through the connector
#   --sha256 NAME=HASH     also require this SHA-256 for release file NAME (repeatable)
#   --version X            tools version to install (default below)
#   --base-url URL         where the release files are (default: this version's GitHub release)
#   --no-service           with --connector: install files and settings, but don't start the connector
#   --print-service        print the connector's LaunchAgent or systemd unit and exit (changes nothing)
#   --uninstall            stop the connector and remove Tern's files from ~/.tern
#
# Every download is checked against the release's SHA256SUMS (and any --sha256 pin) before anything is installed.
# Re-running is safe: unchanged files are left alone, and the connector restarts only when something changed.
# A computer set up with the older separate tern-server and tern-connector programs is converted in place.
# The layout, service names and files are the same as a setup from the Tern iPhone app, so the app's
# "Remove from Tern" cleans up either one.
set -eu
umask 077

VERSION="0.0.1"
REPO_URL="https://github.com/asaasinventuresllc/Tern"
LABEL="com.asaasin.tern-connector"
UNIT="tern-connector"

say()  { printf '%s\n' "$*"; }
die()  { printf 'tern install: %s\n' "$*" >&2; exit 1; }

CONNECTOR=0 ALLOW="" PINS="" BASE_URL="" NO_SERVICE=0 PRINT=0 UNINSTALL=0
while [ $# -gt 0 ]; do
  case "$1" in
    --connector)     CONNECTOR=1; shift ;;
    --allow)         ALLOW="$ALLOW ${2-}"; shift 2 ;;
    --sha256)        PINS="$PINS ${2-}"; shift 2 ;;
    --version)       VERSION=${2-}; shift 2 ;;
    --base-url)      BASE_URL=${2-}; shift 2 ;;
    --no-service)    NO_SERVICE=1; shift ;;
    --print-service) PRINT=1; shift ;;
    --uninstall)     UNINSTALL=1; shift ;;
    -h|--help)       sed -n '2,23p' "$0" 2>/dev/null || say "see the comments at the top of tern-install.sh"; exit 0 ;;
    *) die "unknown option: $1 (try --help)" ;;
  esac
done

[ -n "${HOME:-}" ] && [ -d "$HOME" ] || die "HOME is not set to a folder"
T="$HOME/.tern"
LOG="$T/connector.log"

# Test-only: a different service label, honoured only when HOME is a throwaway folder, so tests never replace a
# real connector (launchd and systemd services belong to the user account, not to HOME).
case "$HOME" in
  /tmp/*|/private/tmp/*|/private/var/folders/*)
    if [ -n "${TERN_INSTALL_TEST_LABEL:-}" ]; then LABEL=$TERN_INSTALL_TEST_LABEL; UNIT=$TERN_INSTALL_TEST_LABEL; fi ;;
esac

OS=$(uname -s); ARCH=$(uname -m)
case "$OS" in
  Darwin) PLATFORM="darwin-universal"; os=darwin ;;
  Linux)
    os=linux
    case "$ARCH" in
      x86_64|amd64)  PLATFORM="linux-x86_64" ;;
      aarch64|arm64) PLATFORM="linux-aarch64" ;;
      *) die "no Tern build for Linux on $ARCH (x86_64 and aarch64 are supported)" ;;
    esac ;;
  *) die "no Tern build for $OS (macOS and Linux are supported)" ;;
esac

sha256() {
  if command -v sha256sum >/dev/null 2>&1; then sha256sum "$1"; else shasum -a 256 "$1"; fi | awk '{print $1}'
}

# --- the connector service: the same text the Tern app writes (ConnectorProvisioner.serviceCommand). No relay
# address or certificate: the published connector has Tern Relay's built in. ----------------------------------
service_text() {
  bin="$T/tern-connector"; server_bin="$T/tern-server"
  if [ "$os" = darwin ]; then
    printf '%s\n' '<?xml version="1.0" encoding="UTF-8"?>' \
      '<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">' \
      '<plist version="1.0"><dict>' \
      "  <key>Label</key><string>$LABEL</string>" \
      "  <key>ProgramArguments</key><array><string>$bin</string></array>" \
      '  <key>EnvironmentVariables</key><dict>' \
      "    <key>HOME</key><string>$HOME</string>" \
      "    <key>TERN_SERVER_BIN</key><string>$server_bin</string>" \
      '  </dict>' \
      '  <key>RunAtLoad</key><true/><key>KeepAlive</key><true/>' \
      "  <key>StandardOutPath</key><string>$LOG</string>" \
      "  <key>StandardErrorPath</key><string>$LOG</string>" \
      '</dict></plist>'
  else
    printf '%s\n' '[Unit]' 'Description=Tern connector' 'After=network-online.target' '[Service]' \
      "ExecStart=$bin" "Environment=TERN_SERVER_BIN=$server_bin" 'Restart=always' 'RestartSec=3' "StandardOutput=append:$LOG" "StandardError=append:$LOG" \
      '[Install]' 'WantedBy=default.target'
  fi
}
service_path() {
  if [ "$os" = darwin ]; then printf '%s' "$HOME/Library/LaunchAgents/$LABEL.plist"
  else printf '%s' "$HOME/.config/systemd/user/$UNIT.service"; fi
}
service_running() {  # running, not just loaded (the same test the app uses)
  if [ "$os" = darwin ]; then launchctl print "gui/$(id -u)/$LABEL" 2>/dev/null | grep -q 'state = running'
  else systemctl --user is-active --quiet "$UNIT" 2>/dev/null; fi
}

# --- uninstall: the same steps as the app's "Remove from Tern", minus the phone's own key lines ----------------
if [ "$UNINSTALL" = 1 ]; then
  p=$(service_path)
  if [ -f "$p" ]; then
    if [ "$os" = darwin ]; then launchctl bootout "gui/$(id -u)" "$p" 2>/dev/null || true
    else systemctl --user disable --now "$UNIT" 2>/dev/null || true; fi
    rm -f "$p"
    if [ "$os" = linux ]; then systemctl --user daemon-reload 2>/dev/null || true; fi
    say "connector service removed"
  fi
  # Like the app: tidy the systemd user folder if removing the unit left it empty (never its parents).
  if [ "$os" = linux ]; then rmdir "$HOME/.config/systemd/user" 2>/dev/null || true; fi
  pkill -u "$(id -u)" -f "$T/tern-connector" 2>/dev/null || true
  if [ -f "$T/connector.key" ]; then
    say "connector.key is this computer's Tern identity: phones that reach it through Tern Relay lose it, and setting it up again gives it a new one"
  fi
  for f in tern tern-server tern-connector tern-cli relay-ca.pem connector.key connector.log .connector.sha; do rm -f "$T/$f"; done
  rmdir "$T/sessions" 2>/dev/null || true
  if rmdir "$T" 2>/dev/null; then say "removed ~/.tern"
  else say "left ~/.tern in place: it still holds other files (e.g. authorized_clients, the phones allowed in)."; fi
  exit 0
fi

# --- phone grants -----------------------------------------------------------------------------------------------
for k in $ALLOW; do
  printf '%s' "$k" | grep -Eq '^[0-9A-Fa-f]{64}$' || die "--allow takes a phone's 64-hex Tern key (got: $k)"
done

if [ "$PRINT" = 1 ]; then service_text; exit 0; fi

# The connector checks Tern Relay's certificate against the system's trusted certificates. macOS always has them;
# on Linux they come from the ca-certificates package, so check before changing anything.
if [ "$CONNECTOR" = 1 ] && [ "$os" = linux ]; then
  found=""
  for f in "${SSL_CERT_FILE:-}" /etc/ssl/certs/ca-certificates.crt /etc/pki/tls/certs/ca-bundle.crt \
           /etc/pki/ca-trust/extracted/pem/tls-ca-bundle.pem /etc/ssl/ca-bundle.pem /etc/ssl/cert.pem; do
    [ -n "$f" ] && [ -s "$f" ] && { found=$f; break; }
  done
  [ -n "$found" ] || die "no trusted certificates found (e.g. /etc/ssl/certs/ca-certificates.crt): install your system's ca-certificates package, then run this again"
fi

# --- download and verify ----------------------------------------------------------------------------------------
[ -n "$BASE_URL" ] || BASE_URL="$REPO_URL/releases/download/v$VERSION"
case "$BASE_URL" in
  https://*|http://127.0.0.1[:/]*|http://localhost[:/]*) ;;
  *) die "--base-url must be https (or a local http test server)" ;;
esac
fetch() {
  if command -v curl >/dev/null 2>&1; then curl -fsSL -o "$2" "$1"
  elif command -v wget >/dev/null 2>&1; then wget -q -O "$2" "$1"
  else die "needs curl or wget"; fi
}
TMP=$(mktemp -d "${TMPDIR:-/tmp}/tern-install.XXXXXX")
trap 'rm -rf "$TMP"' EXIT INT TERM

say "Tern tools $VERSION for $PLATFORM"
fetch "$BASE_URL/SHA256SUMS" "$TMP/SHA256SUMS" || die "couldn't download SHA256SUMS from $BASE_URL"

for pin in $PINS; do
  name=${pin%%=*}; hash=${pin#*=}
  printf '%s' "$hash" | grep -Eq '^[0-9A-Fa-f]{64}$' && [ "$name" != "$pin" ] || die "--sha256 takes NAME=64-hex (got: $pin)"
  awk -v n="$name" '$2 == n { f = 1 } END { exit !f }' "$TMP/SHA256SUMS" || die "--sha256 names $name, which isn't in this release"
done

TOOLS="tern tern-cli"
for tool in $TOOLS; do
  name="$tool-$PLATFORM"
  want=$(awk -v n="$name" '$2 == n { print $1 }' "$TMP/SHA256SUMS")
  [ -n "$want" ] || die "SHA256SUMS has no entry for $name"
  pinned=""
  for pin in $PINS; do [ "${pin%%=*}" = "$name" ] && pinned=${pin#*=}; done
  if [ -n "$pinned" ] && [ "$(printf '%s' "$pinned" | tr A-F a-f)" != "$(printf '%s' "$want" | tr A-F a-f)" ]; then
    die "$name: the pinned SHA-256 doesn't match this release's SHA256SUMS; refusing"
  fi
  if [ -f "$T/$tool" ] && [ "$(sha256 "$T/$tool")" = "$want" ]; then
    say "  $tool: already installed"
    continue
  fi
  fetch "$BASE_URL/$name" "$TMP/$tool" || die "couldn't download $name"
  got=$(sha256 "$TMP/$tool")
  [ "$got" = "$want" ] || die "$name: SHA-256 mismatch (got $got, want $want); refusing"
  touch "$TMP/.changed-$tool"
done

# --- install (only after every download verified) --------------------------------------------------------------
mkdir -p "$T" && chmod 700 "$T"
for tool in $TOOLS; do
  [ -f "$TMP/.changed-$tool" ] || continue
  # Swapped in by rename, like the app: running sessions keep the file they started from.
  cp "$TMP/$tool" "$T/.$tool.new" && chmod 755 "$T/.$tool.new" && mv -f "$T/.$tool.new" "$T/$tool"
  say "  $tool: installed"
done
# tern-server and tern-connector are links to tern (the app's BinaryInstall.linkCommand), each made under a
# temporary name and renamed into place. This also replaces the separate programs of an older install.
for l in tern-server tern-connector; do
  ln -sfn tern "$T/.$l.link" && mv -f "$T/.$l.link" "$T/$l"
done
TERN_SHA=$(sha256 "$T/tern")
MARKER="$T/.connector.sha"

for k in $ALLOW; do
  grant="$(printf '%s' "$k" | tr A-F a-f) tern-bootstrap"
  touch "$T/authorized_clients" && chmod 600 "$T/authorized_clients"
  grep -qxF "$grant" "$T/authorized_clients" || { printf '%s\n' "$grant" >> "$T/authorized_clients"; say "  allowed phone ${k%"${k#????????????}"}…"; }
done

# --- the connector service --------------------------------------------------------------------------------------
if [ "$CONNECTOR" = 0 ]; then
  say "Installed in ~/.tern. To reach this computer from anywhere, run this again with --connector."
  say "Add ~/.tern to your PATH to use the tern-cli command-line tool."
  say "Licenses: $REPO_URL/releases/download/v$VERSION/NOTICE and …/THIRD_PARTY_NOTICES"
  exit 0
fi
if [ "$NO_SERVICE" = 1 ]; then say "Installed; the connector service was not started (--no-service)."; exit 0; fi

# Like the app (ConnectorProvisioner.serviceCommand): stage the service file, and (re)start the connector only when
# its service file changed, it isn't running, or it was started from a different `tern` than the one installed now
# (~/.tern/.connector.sha records the SHA-256 it started with). A re-run with nothing new restarts nothing.
SP=$(service_path)
if [ "$os" = linux ]; then
  systemctl --user show-environment >/dev/null 2>&1 \
    || die "no systemd user session here (containers, WSL1): rerun with --no-service and start ~/.tern/tern-connector yourself"
  mkdir -p "$HOME/.config/systemd/user"
  loginctl enable-linger "${USER:-$(id -un)}" 2>/dev/null || true
else
  mkdir -p "$HOME/Library/LaunchAgents"
fi
umask 022; service_text > "$SP.tern-new"; umask 077
start_service() {  # $1 = 1 to force a restart; prints what it did, returns 0 when it (re)started the connector
  if [ "$1" = 1 ] || [ "$(cat "$MARKER" 2>/dev/null)" != "$TERN_SHA" ] || ! cmp -s "$SP.tern-new" "$SP" 2>/dev/null \
     || ! service_running; then
    mv -f "$SP.tern-new" "$SP"
    if [ "$os" = darwin ]; then
      launchctl bootout "gui/$(id -u)" "$SP" 2>/dev/null || true
      : > "$LOG"
      launchctl bootstrap "gui/$(id -u)" "$SP" || die "launchctl couldn't start the connector"
      printf '%s' "$TERN_SHA" > "$MARKER"
      say "  connector: LaunchAgent started"
    else
      : > "$LOG"
      systemctl --user daemon-reload
      systemctl --user enable "$UNIT" >/dev/null 2>&1 || die "systemctl couldn't enable the connector"
      systemctl --user restart "$UNIT" || die "systemctl couldn't start the connector"
      printf '%s' "$TERN_SHA" > "$MARKER"
      say "  connector: systemd user unit started"
    fi
    return 0
  fi
  rm -f "$SP.tern-new"
  if [ "$os" = linux ]; then systemctl --user enable "$UNIT" >/dev/null 2>&1 || true; fi
  say "  connector: already running, unchanged"
  return 1
}
restarted=0
if start_service 0; then restarted=1; fi

# The connector prints "endpoint id = <hex>" on startup (the same readback the app does). If the log no longer has
# it (the connector was left running), restart it once so it logs its id again, as the app does.
read_id() {
  id=""
  for _ in 1 2 3 4 5 6; do
    sleep 1
    id=$(grep 'endpoint id = ' "$LOG" 2>/dev/null | tail -1 | sed 's/.*endpoint id = //')
    printf '%s' "$id" | grep -Eq '^[0-9a-f]{64}$' && return 0
    id=""
  done
  return 1
}
if ! read_id && [ "$restarted" = 0 ]; then
  umask 022; service_text > "$SP.tern-new"; umask 077
  start_service 1 || true
  read_id || true
fi
[ -n "$id" ] || die "the connector started but didn't report an endpoint id; see ~/.tern/connector.log"
say ""
say "This computer's endpoint id: $id"
say "Add it in the Tern app to reach this computer from anywhere."
