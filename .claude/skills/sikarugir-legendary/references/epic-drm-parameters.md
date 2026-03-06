# Epic DRM Parameters Reference

## Required Command-Line Arguments

When launching an Epic game with DRM, the following arguments must be passed to the game executable:

### Authentication Arguments

| Argument | Description | Example Value |
|----------|-------------|---------------|
| `-AUTH_LOGIN=unused` | Placeholder for login (always "unused") | `unused` |
| `-AUTH_PASSWORD=<code>` | Exchange code from legendary | `abc123def456...` |
| `-AUTH_TYPE=exchangecode` | Authentication type | `exchangecode` |

### Epic Platform Arguments

| Argument | Description | Source |
|----------|-------------|--------|
| `-epicapp=<APP_ID>` | Application ID | `legendary info --json` → `app_name` |
| `-epicenv=Prod` | Environment | Always `Prod` |
| `-EpicPortal` | Enable Epic portal features | Flag only |
| `-epicusername=<name>` | Epic display name | `user.json` → `displayName` |
| `-epicuserid=<id>` | Epic account ID | `user.json` → `account_id` |
| `-epiclocale=en` | Language/locale | Usually `en` |
| `-epicsandboxid=<NAMESPACE>` | Game namespace | `legendary info --json` → `asset_infos.Windows.namespace` |
| `-epicdeploymentid=<ID>` | Deployment ID | From legendary dry-run output |

## Finding Game Identifiers

### Using legendary CLI

```bash
# List all installed games
legendary list

# Get detailed info for a specific game
legendary info <game_name> --json
```

### JSON Output Structure

```json
{
  "app_name": "GAME_ID",
  "app_title": "Game Title",
  "asset_infos": {
    "Windows": {
      "app_name": "APP_ID",
      "namespace": "NAMESPACE",
      "catalog_item_id": "CATALOG_ID"
    }
  }
}
```

### Identifier Mapping

| Identifier | JSON Path | Used For |
|------------|-----------|----------|
| GAME_ID | `app_name` | legendary commands |
| APP_ID | `asset_infos.Windows.app_name` | `-epicapp` argument |
| NAMESPACE | `asset_infos.Windows.namespace` | `-epicsandboxid`, .ovt path |
| CATALOG_ID | `asset_infos.Windows.catalog_item_id` | .ovt path |

## File Locations

### User Configuration
```
~/.config/legendary/user.json
```

Contains:
- `account_id` - Epic account identifier
- `displayName` - Epic username
- `session_id` - Current session

### Ownership Verification Token (.ovt)
```
~/.config/legendary/game_metadata/<NAMESPACE>/<CATALOG_ID>.ovt
```

This file proves game ownership. Must exist for DRM check to pass.

### Game Installation
```
~/Games/<GameName>/
```

Default legendary installation path (can be customized).

## Getting Fresh Exchange Code

The exchange code is temporary and must be generated at launch time:

```bash
legendary launch <game_name> --dry-run 2>&1
```

Parse the output for `-AUTH_PASSWORD=` to extract the current exchange code.

## Game-Specific Flags

Some games require additional arguments:

| Game | Additional Flags |
|------|------------------|
| Most games | `-SaveToUserDir -UserDir=<GameName>` |
| Alan Wake 2 | Standard flags |
| Fortnite | `-epicuserid` required |

## Deployment ID

The deployment ID can be found in:
1. The dry-run output from legendary
2. Game metadata files
3. The game's EOS SDK configuration

```bash
legendary launch <game> --dry-run 2>&1 | grep -o 'epicdeploymentid=[^[:space:]]*'
```

## Environment Variables

Some games also check these environment variables:

| Variable | Description |
|----------|-------------|
| `EPIC_OVERLAY_PATH` | Path to Epic overlay DLL |
| `EOS_PLATFORM_INSTANCE` | EOS platform identifier |

## Troubleshooting

### "Invalid Exchange Code"
- Code expired (valid for ~5 minutes)
- Generate fresh code immediately before launch

### "Ownership Verification Failed"
- .ovt file missing or corrupted
- Re-verify ownership: `legendary verify-ownership <game>`

### "Authentication Failed"
- Re-authenticate legendary: `legendary auth`
- Check `user.json` exists and is valid
