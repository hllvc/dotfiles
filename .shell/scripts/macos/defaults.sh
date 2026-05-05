#!/usr/bin/env bash

# Apply personal macOS `defaults write` tweaks. Idempotent — safe to re-run.
#
# Entrypoint: ./dotctl macos apply
#
# Adding a new tweak:
#   1. Change the setting in System Settings (or via `defaults write` ad-hoc).
#   2. Inspect: `defaults read <domain> <key>` — note the type (bool/int/string/float).
#   3. Append a `defaults write` line in the right section below; if the value
#      is a non-obvious enum (hot corners, view styles, search scopes), add a
#      short inline comment so future-you doesn't have to look it up.
#   4. Run `./dotctl macos apply` to verify.

set -euo pipefail

echo "── applying macOS defaults ──"

# ─── NSGlobalDomain — UI / input ───────────────────────────────────────── {{{

defaults write NSGlobalDomain AppleShowAllExtensions -bool true
defaults write NSGlobalDomain NSWindowResizeTime -float 0.1 # snappier window resize animation
defaults write NSGlobalDomain KeyRepeat -int 1              # fastest key repeat rate
defaults write NSGlobalDomain InitialKeyRepeat -int 10      # shortest delay before repeat starts
defaults write NSGlobalDomain NSAutomaticSpellingCorrectionEnabled -bool false
defaults write NSGlobalDomain NSAutomaticCapitalizationEnabled -bool false
defaults write NSGlobalDomain NSAutomaticQuoteSubstitutionEnabled -bool false
defaults write NSGlobalDomain com.apple.trackpad.scaling -float 2.5      # tracking speed (max ~3.0)
defaults write NSGlobalDomain com.apple.swipescrolldirection -bool false # natural scrolling OFF

# }}}

# ─── Finder ────────────────────────────────────────────────────────────── {{{

defaults write com.apple.finder ShowPathbar -bool true
defaults write com.apple.finder ShowStatusBar -bool true
defaults write com.apple.finder FXPreferredViewStyle -string clmv # column view (icnv|Nlsv|clmv|Flwv)
defaults write com.apple.finder FXDefaultSearchScope -string SCcf # search current folder (SCev=this Mac, SCcf=current, SCsp=previous)

# }}}

# ─── Dock ──────────────────────────────────────────────────────────────── {{{

defaults write com.apple.dock autohide -bool true
defaults write com.apple.dock tilesize -int 54
defaults write com.apple.dock mineffect -string scale   # minimize effect (genie|scale|suck)
defaults write com.apple.dock scroll-to-open -bool true # scroll up on dock icon to expand stack / show windows
defaults write com.apple.dock mru-spaces -bool false    # don't auto-rearrange Spaces by recent use

# Hot corner action codes:
#   1=disabled  2=Mission Control  3=Application Windows  4=Desktop
#   5=Start Screen Saver  6=Disable Screen Saver  7=Dashboard (legacy)
#   10=Put Display to Sleep  11=Launchpad  12=Notification Center
#   13=Lock Screen  14=Quick Note
defaults write com.apple.dock wvous-tl-corner -int 4  # top-left → Desktop
defaults write com.apple.dock wvous-tr-corner -int 1  # top-right → disabled
defaults write com.apple.dock wvous-bl-corner -int 14 # bottom-left → Quick Note
defaults write com.apple.dock wvous-br-corner -int 14 # bottom-right → Quick Note

# }}}

# ─── Trackpad ──────────────────────────────────────────────────────────── {{{

defaults write com.apple.AppleMultitouchTrackpad Clicking -bool true # tap to click
defaults write com.apple.AppleMultitouchTrackpad TrackpadThreeFingerDrag -bool true

# }}}

# ─── Safari ────────────────────────────────────────────────────────────── {{{

defaults write com.apple.Safari ShowFullURLInSmartSearchField -bool true
defaults write com.apple.Safari IncludeDevelopMenu -bool true
defaults write com.apple.Safari ShowOverlayStatusBar -bool true

# }}}

# ─── Mail ──────────────────────────────────────────────────────────────── {{{

defaults write com.apple.mail DisableInlineAttachmentViewing -bool true # show attachments as icons, not inline previews

# }}}

# ─── Apply ─────────────────────────────────────────────────────────────── {{{

# Some prefs only take effect after the owning process restarts; flushing
# cfprefsd avoids stale-cache reads from other processes.
killall Dock Finder SystemUIServer cfprefsd 2>/dev/null || true

echo "── done ──"

# }}}
