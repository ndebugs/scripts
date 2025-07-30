#!/bin/bash

DEFAULT_DOMAIN="MYDOMAIN.COM"
DEFAULT_DOMAIN_CONTROLLER_PREFIX="DC01"

SCRIPT_DIR="$HOME/scripts"
SCRIPT_PATH="$SCRIPT_DIR/adrefresh.sh"
LABEL="com.ndebugs.adrefresh"
PLIST_PATH="$HOME/Library/LaunchAgents/$LABEL.plist"
INTERVAL=60  # seconds
PING_TIMEOUT=1
LOG_BASE="$HOME/Library/Logs/$LABEL"
LOG_MAX_SIZE=1048576  # 1 MB
LOG_MIN_LINES=100

init_password() {
  # Check if password already exists in keychain
  if ! security find-generic-password -a "$USERNAME" -s "$DOMAIN" >/dev/null 2>&1; then
    echo "Password not found in keychain for $USERNAME"
    read -s -p "Enter your AD password: " AD_PASSWORD
    echo

    security add-generic-password -a "$USERNAME" -s "$DOMAIN" -w "$AD_PASSWORD" -T /usr/bin/kinit
    echo "Password saved to keychain under service \"$DOMAIN\""
  fi
}

init_script() {
  mkdir -p "$SCRIPT_DIR"

  # Generate the refresh script if missing
  if [ ! -f "$SCRIPT_PATH" ]; then
    echo "Generating $SCRIPT_PATH ..."
    cat > "$SCRIPT_PATH" <<EOF
#!/bin/bash

DOMAIN=$DOMAIN
DOMAIN_CONTROLLER=$DOMAIN_CONTROLLER
USERNAME=$USERNAME

timestamp() {
  date '+%Y-%m-%d %H:%M:%S'
}

check_log() {
  if [ -f "\$1" ] && [ "\$(stat -f%z "\$1")" -gt "$LOG_MAX_SIZE" ]; then
    echo "[\$(timestamp)] Log max size exceeded." >> "\$1"
    tail -n "$LOG_MIN_LINES" "\$1" > "\$1.tmp" && mv "\$1.tmp" "\$1"
  fi
}

check_ad() {
  if ! ping -c 1 -t $PING_TIMEOUT "\$DOMAIN_CONTROLLER" >/dev/null 2>&1; then
    echo "[\$(timestamp)] AD check failed." >&2
    return 1
  fi

  return \$?
}

check_internet() {
  if ! ping -c 1 -t $PING_TIMEOUT 8.8.8.8 >/dev/null 2>&1; then
    echo "[\$(timestamp)] Internet check failed." >&2
    return 1
  fi

  return \$?
}

echo "[\$(timestamp)] Executing script ..."

check_log "$LOG_BASE.log"
check_log "$LOG_BASE.err"

if ! check_ad; then
  echo "[\$(timestamp)] Not connected to \$DOMAIN_CONTROLLER. Exiting ..."
  exit 0
fi

if ! check_internet; then
  if klist -s 2>/dev/null; then
    echo "[\$(timestamp)] Destroying ticket ..."
    kdestroy
  fi

  echo "[\$(timestamp)] Creating ticket ..."
  kinit --keychain "\$USERNAME@\$DOMAIN"
fi
EOF

    chmod +x "$SCRIPT_PATH"
    echo "Script created and made executable."
  fi
}

init_plist() {
  # Create LaunchAgent plist if missing
  if [ ! -f "$PLIST_PATH" ]; then
    echo "Creating LaunchAgent plist ..."
    mkdir -p "$HOME/Library/LaunchAgents"

    cat > "$PLIST_PATH" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key>
  <string>$LABEL</string>
  <key>ProgramArguments</key>
  <array>
    <string>$SCRIPT_PATH</string>
  </array>
  <key>KeepAlive</key>
  <dict>
    <key>NetworkState</key>
    <true/>
  </dict>
  <key>StartInterval</key>
  <integer>$INTERVAL</integer>
  <key>RunAtLoad</key>
  <true/>
  <key>StandardOutPath</key>
  <string>$LOG_BASE.log</string>
  <key>StandardErrorPath</key>
  <string>$LOG_BASE.err</string>
</dict>
</plist>
EOF

    echo "LaunchAgent plist created."
  fi

  # Load LaunchAgent if not already loaded
  if launchctl list | grep "$LABEL"; then
    launchctl unload "$PLIST_PATH"
    echo "LaunchAgent was already loaded, now reloading ..."
  fi

  launchctl load "$PLIST_PATH"
  echo "LaunchAgent loaded."
}

install() {
  read -p "Enter domain [$DEFAULT_DOMAIN]: " DOMAIN
  DOMAIN="${DOMAIN:-$DEFAULT_DOMAIN}"
  echo "Using domain: $DOMAIN"
  echo

  read -p "Enter domain controller [$DEFAULT_DOMAIN_CONTROLLER_PREFIX.$DOMAIN]: " DOMAIN_CONTROLLER
  DOMAIN_CONTROLLER="${DOMAIN_CONTROLLER:-$DEFAULT_DOMAIN_CONTROLLER_PREFIX.$DOMAIN}"
  echo "Using domain controller: $DOMAIN_CONTROLLER"
  echo

  read -p "Enter AD username [$USER]: " USERNAME
  USERNAME="${USERNAME:-$USER}"
  echo "Using AD username: $USERNAME"
  echo

  init_password
  init_script
  init_plist
}

uninstall() {
  if [ -f "$PLIST_PATH" ]; then
    launchctl unload "$PLIST_PATH"
    rm "$PLIST_PATH"

    echo "LaunchAgent plist removed."
  fi

  [ -f "$LOG_BASE.log" ] && rm "$LOG_BASE.log"
  [ -f "$LOG_BASE.err" ] && rm "$LOG_BASE.err"

  if [ -f "$SCRIPT_PATH" ]; then
    rm "$SCRIPT_PATH"
    echo "Script removed."
  fi
}

case "$1" in
  install)
    install
    ;;
  uninstall)
    uninstall
    ;;
  *)
    echo "Usage: $0 {install|uninstall}"
    exit 1
    ;;
esac
