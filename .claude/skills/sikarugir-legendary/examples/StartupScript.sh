#!/bin/bash
# StartupScript for Sikarugir + Legendary Integration
# Place this file at: <APP_PATH>/Contents/Resources/StartupScript
#
# Replace placeholders before use:
#   {{GAME_ID}}     - legendary game identifier (e.g., "AlanWake2")
#   {{APP_ID}}      - Epic app ID (usually same as GAME_ID)
#   {{NAMESPACE}}   - Epic namespace from game metadata
#   {{CATALOG_ID}}  - Catalog item ID from game metadata
#   {{GAME_DIR}}    - Game directory name for -UserDir flag
#   {{ACCOUNT_ID}}  - Epic account ID from user.json

# Configuration - Replace these placeholders
GAME_ID="{{GAME_ID}}"
APP_ID="{{APP_ID}}"
NAMESPACE="{{NAMESPACE}}"
CATALOG_ID="{{CATALOG_ID}}"
GAME_DIR="{{GAME_DIR}}"

# Paths
LEGENDARY_CONFIG="$HOME/.config/legendary"
USER_JSON="$LEGENDARY_CONFIG/user.json"
OVT_FILE="$LEGENDARY_CONFIG/game_metadata/$NAMESPACE/$CATALOG_ID.ovt"
APP_PATH="$(dirname "$(dirname "$(dirname "$0")")")"
INFO_PLIST="$APP_PATH/Contents/Info.plist"

# Logging
log() {
  echo "[StartupScript] $1"
}

# Check prerequisites
if [ ! -f "$USER_JSON" ]; then
  log "ERROR: user.json not found. Run 'legendary auth' first."
  exit 1
fi

if [ ! -f "$OVT_FILE" ]; then
  log "WARNING: .ovt file not found at $OVT_FILE"
  log "Game ownership verification may fail."
fi

# Get user info from legendary config
EPIC_USERNAME=$(python3 -c "import json; print(json.load(open('$USER_JSON'))['displayName'])" 2>/dev/null)
EPIC_USERID=$(python3 -c "import json; print(json.load(open('$USER_JSON'))['account_id'])" 2>/dev/null)

if [ -z "$EPIC_USERNAME" ] || [ -z "$EPIC_USERID" ]; then
  log "ERROR: Could not read user info from $USER_JSON"
  exit 1
fi

log "Epic User: $EPIC_USERNAME ($EPIC_USERID)"

# Run legendary dry-run to get fresh exchange code
log "Refreshing authentication tokens..."
DRY_RUN_OUTPUT=$(legendary launch "$GAME_ID" --dry-run 2>&1)

if [ $? -ne 0 ]; then
  log "ERROR: legendary dry-run failed"
  echo "$DRY_RUN_OUTPUT"
  exit 1
fi

# Extract exchange code from dry-run output
EXCHANGE_CODE=$(echo "$DRY_RUN_OUTPUT" | grep -o '\-AUTH_PASSWORD=[^[:space:]]*' | cut -d= -f2)

if [ -z "$EXCHANGE_CODE" ]; then
  log "ERROR: Could not extract exchange code from legendary output"
  echo "$DRY_RUN_OUTPUT"
  exit 1
fi

log "Got fresh exchange code"

# Extract deployment ID if available
DEPLOYMENT_ID=$(echo "$DRY_RUN_OUTPUT" | grep -o '\-epicdeploymentid=[^[:space:]]*' | cut -d= -f2)

# Build the Epic DRM arguments
EPIC_ARGS=(
  "-AUTH_LOGIN=unused"
  "-AUTH_PASSWORD=$EXCHANGE_CODE"
  "-AUTH_TYPE=exchangecode"
  "-epicapp=$APP_ID"
  "-epicenv=Prod"
  "-EpicPortal"
  "-epicusername=$EPIC_USERNAME"
  "-epicuserid=$EPIC_USERID"
  "-epiclocale=en"
  "-epicsandboxid=$NAMESPACE"
)

# Add deployment ID if found
if [ -n "$DEPLOYMENT_ID" ]; then
  EPIC_ARGS+=("-epicdeploymentid=$DEPLOYMENT_ID")
fi

# Add game-specific flags
EPIC_ARGS+=(
  "-SaveToUserDir"
  "-UserDir=$GAME_DIR"
)

# Convert to space-separated string for Info.plist
ARGS_STRING=""
for arg in "${EPIC_ARGS[@]}"; do
  ARGS_STRING="$ARGS_STRING $arg"
done
ARGS_STRING="${ARGS_STRING# }"  # Remove leading space

log "Updating Info.plist with Epic arguments..."

# Read current programArguments from Info.plist
# This uses PlistBuddy to update the arguments

# First, check if programArguments exists
if /usr/libexec/PlistBuddy -c "Print :programArguments" "$INFO_PLIST" &>/dev/null; then
  # Get current argument count
  ARG_COUNT=$(/usr/libexec/PlistBuddy -c "Print :programArguments" "$INFO_PLIST" | grep -c "^    ")

  # Remove any existing Epic arguments (those starting with -)
  # We'll add them fresh each time
  for ((i=ARG_COUNT-1; i>=0; i--)); do
    ARG=$(/usr/libexec/PlistBuddy -c "Print :programArguments:$i" "$INFO_PLIST" 2>/dev/null)
    if [[ "$ARG" == -AUTH_* ]] || [[ "$ARG" == -epic* ]] || [[ "$ARG" == -Epic* ]] || [[ "$ARG" == -Save* ]] || [[ "$ARG" == -User* ]]; then
      /usr/libexec/PlistBuddy -c "Delete :programArguments:$i" "$INFO_PLIST" 2>/dev/null
    fi
  done

  # Add new Epic arguments
  for arg in "${EPIC_ARGS[@]}"; do
    /usr/libexec/PlistBuddy -c "Add :programArguments: string '$arg'" "$INFO_PLIST"
  done

  log "Info.plist updated successfully"
else
  log "WARNING: programArguments not found in Info.plist"
  log "You may need to add arguments manually"
fi

log "StartupScript completed"
exit 0
