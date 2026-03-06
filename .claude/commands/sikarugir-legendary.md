# Sikarugir Legendary Integration

Manage Epic Games integration for Sikarugir-wrapped games (Wine wrappers with Epic DRM).

## Context

This skill handles setup and maintenance of Epic Games authentication and cloud saves for games running via Sikarugir (a Wine wrapper for macOS).

## App Location
`~/Applications/Sikarugir/HogwartsLegacy.app`

## Key Files

### UpdateToken.sh
Location: `Contents/MacOS/UpdateToken.sh`

Refreshes Epic auth token and updates Info.plist with Program Flags:
- Gets exchange code via `legendary get-token`
- Copies OVT file to Wine prefix
- Updates Info.plist with auth parameters

### StartupScript
Location: `Contents/Resources/Scripts/StartupScript`

Downloads cloud saves before game starts:
```bash
legendary sync-saves --skip-upload --force-download --save-path "$SAVE_PATH" <game_id>
```

### ShutdownScript
Location: `Contents/Resources/Scripts/ShutdownScript`

Uploads cloud saves after game quits:
```bash
legendary sync-saves --skip-download --force-upload --save-path "$SAVE_PATH" <game_id>
```

## Game Identifiers (Hogwarts Legacy)
- **Game ID**: `fa4240e57a3c46b39f169041b7811293`
- **Namespace**: `e97659b501af4e3981d5430dad170911`
- **Catalog ID**: `864c7bc2c2394f7dbd1b534aa068ff56`

## Save Path
```
Contents/SharedSupport/prefix/drive_c/users/Sikarugir/AppData/Local/HogwartsLegacy/Saved/SaveGames/458801f5e8fd4ed0bbc1dc1b48e32ef8
```

## Logs
All logs are in `Contents/Logs/` (symlink to `SharedSupport/Logs/`):
- `UpdateToken.log`
- `StartupScript.log`
- `ShutdownScript.log`

## Common Tasks

### Check logs
```bash
cat ~/Applications/Sikarugir/HogwartsLegacy.app/Contents/Logs/UpdateToken.log
cat ~/Applications/Sikarugir/HogwartsLegacy.app/Contents/Logs/StartupScript.log
cat ~/Applications/Sikarugir/HogwartsLegacy.app/Contents/Logs/ShutdownScript.log
```

### Manual token refresh
```bash
~/Applications/Sikarugir/HogwartsLegacy.app/Contents/MacOS/UpdateToken.sh
```

### Manual cloud save sync
```bash
# Download
legendary sync-saves --skip-upload --force-download fa4240e57a3c46b39f169041b7811293

# Upload
legendary sync-saves --skip-download --force-upload fa4240e57a3c46b39f169041b7811293
```

### Re-authenticate with Epic
```bash
legendary auth
```

### List cloud saves
```bash
legendary list-saves
```

## Program Flags Template
```
-AUTH_LOGIN=unused -AUTH_PASSWORD=<exchange_code> -AUTH_TYPE=exchangecode -epicapp=<game_id> -epicenv=Prod -EpicPortal -epicusername=<username> -epicuserid=<user_id> -epiclocale=en-US -epicsandboxid=<namespace> -epicovt=<ovt_path> -SaveToUserDir -UserDir=HogwartsLegacy
```
