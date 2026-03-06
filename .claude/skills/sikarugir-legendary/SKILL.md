# Sikarugir Legendary Integration Skill

---
name: sikarugir-legendary
description: integrate legendary with sikarugir, setup epic drm for sikarugir, add legendary authentication, sikarugir epic game, configure sikarugir for epic, epic drm wrapper
version: 1.0.0
---

## Purpose

This skill automates integrating Epic Games Store games wrapped with Sikarugir to use the `legendary` CLI for DRM authentication instead of the Epic Games Launcher.

## Prerequisites

- **legendary CLI** installed and authenticated (`legendary auth`)
- **Sikarugir** wrapper app already created for the game
- Game already installed via legendary (`legendary install <game>`)

## Workflow

### Step 1: Gather Information

Ask the user for:
1. **Sikarugir app path** (e.g., `/Applications/Sikarugir/GameName.app`)
2. **Game name** as known to legendary (run `legendary list` to find it)

### Step 2: Get Game Identifiers

Run legendary to get the required identifiers:

```bash
legendary info <game_name> --json
```

Extract these values from the output:
- `app_name` → Used as GAME_ID
- `asset_infos.Windows.app_name` → APP_ID (usually same as app_name)
- `asset_infos.Windows.namespace` → NAMESPACE
- `asset_infos.Windows.catalog_item_id` → CATALOG_ID

### Step 3: Get Account Information

Read the Epic account ID from legendary's config:

```bash
cat ~/.config/legendary/user.json
```

Extract `account_id` from the JSON.

### Step 4: Locate the .ovt File

The ownership verification token is stored at:
```
~/.config/legendary/game_metadata/<NAMESPACE>/<CATALOG_ID>.ovt
```

Verify this file exists before proceeding.

### Step 5: Create StartupScript

Create a `StartupScript` in the Sikarugir app bundle at:
```
<APP_PATH>/Contents/Resources/StartupScript
```

Use the template from `examples/StartupScript.sh` with the gathered values.

The script should:
1. Run `legendary launch <game> --dry-run` to refresh authentication tokens
2. Parse the output to get current auth parameters
3. Update Info.plist with Epic DRM arguments

### Step 6: Configure Info.plist

The StartupScript will add these arguments to Info.plist `programArguments`:

```
-AUTH_LOGIN=unused
-AUTH_PASSWORD=<exchange_code>
-AUTH_TYPE=exchangecode
-epicapp=<APP_ID>
-epicenv=Prod
-EpicPortal
-epicusername=<username>
-epicuserid=<user_id>
-epiclocale=en
-epicsandboxid=<NAMESPACE>
-epicdeploymentid=<DEPLOYMENT_ID>
```

Plus game-specific flags like `-SaveToUserDir -UserDir=<GameDir>`

### Step 7: Setup Game Directory Symlink

Create a symlink from the Wine prefix to the actual game installation:

```bash
ln -sf "/path/to/legendary/installed/GameName" "<APP_PATH>/Contents/Resources/drive_c/Games/GameName"
```

### Step 8: Verify Configuration

1. Run the StartupScript manually to test token refresh
2. Check Info.plist was updated with auth arguments
3. Test launching the app

## Reference Files

- See `references/epic-drm-parameters.md` for detailed parameter documentation
- See `examples/StartupScript.sh` for the script template

## Common Issues

### Token Refresh Fails
- Ensure legendary is authenticated: `legendary auth`
- Check internet connection

### Game Crashes on DRM Check
- Verify the .ovt file exists
- Check all identifiers match the game metadata
- Ensure the exchange code is fresh (generated just before launch)

### Wrong Game Directory
- Verify symlink points to correct legendary installation path
- Check the executable path in Info.plist matches the actual binary

## Example Usage

User: "Help me integrate legendary with my Sikarugir-wrapped Alan Wake 2"

1. Get app path: `/Applications/Sikarugir/AlanWake2.app`
2. Run: `legendary info AlanWake2 --json`
3. Extract identifiers from JSON output
4. Create StartupScript with values
5. Setup symlink to legendary's game installation
6. Test launch
