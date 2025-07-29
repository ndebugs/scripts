#!/bin/bash

DEFAULT_DOMAIN="MYDOMAIN.COM"
DEFAULT_DOMAIN_CONTROLLER_PREFIX="DC01"

SCRIPT_DIR="$HOME/scripts"
SCRIPT_PATH="$SCRIPT_DIR/adrefresh.sh"
LABEL="com.ndebugs.adrefresh"
PLIST_PATH="$HOME/Library/LaunchAgents/$LABEL.plist"
INTERVAL=60  # seconds
PING_TIMEOUT=1

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
    echo "Generating $SCRIPT_PATH..."
    cat > "$SCRIPT_PATH" <<EOF
#!/bin/bash

DOMAIN=$DOMAIN
DOMAIN_CONTROLLER=$DOMAIN_CONTROLLER
USERNAME=$USERNAME

check_ad() {
  ping -c 1 -t $PING_TIMEOUT "\$DOMAIN_CONTROLLER" >/dev/null 2>&1
  return $?
}

check_internet() {
  ping -c 1 -t $PING_TIMEOUT 8.8.8.8 >/dev/null 2>&1
  return $?
}

if ! check_ad; then
  echo "\$(date): Not connected to \$DOMAIN_CONTROLLER. Exiting."
  exit 0
fi

if ! check_internet; then
  if klist -s 2>/dev/null; then
    echo "\$(date): Destroying ticket..."
    kdestroy
  fi

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
    echo "Creating LaunchAgent plist..."
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
  <string>$HOME/Library/Logs/$LABEL.log</string>
  <key>StandardErrorPath</key>
  <string>$HOME/Library/Logs/$LABEL.err</string>
</dict>
</plist>
EOF

    echo "LaunchAgent plist created."
  fi

  # Load LaunchAgent if not already loaded
  if launchctl list | grep "$LABEL"; then
    launchctl unload "$PLIST_PATH"
    echo "LaunchAgent was already loaded, now reloading..."
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

  [ -f "$HOME/Library/Logs/$LABEL.log" ] && rm "$HOME/Library/Logs/$LABEL.log"
  [ -f "$HOME/Library/Logs/$LABEL.err" ] && rm "$HOME/Library/Logs/$LABEL.err"

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