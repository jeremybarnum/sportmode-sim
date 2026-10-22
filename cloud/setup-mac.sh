#!/bin/sh
# Readies a rented Mac to run the bench as a GitHub self-hosted runner, after Xcode is installed:
# its licence and first launch, the iOS and watchOS Simulators, developer tools without a password
# prompt (the tap drivers), Homebrew and xcodegen, and no sleep. Asks for the account's password once.
# Then: register the runner (repository Settings, Actions, Runners, label bench-mac) and ./run.sh it.
set -u
say() { printf '\n== %s\n' "$*"; }

say "this Mac"
sw_vers; uname -m; xcodebuild -version; df -h ~ | tail -1
sudo -v || { echo "no admin rights on this account: tell Claude"; exit 1; }

say "Xcode: licence and first launch"
sudo xcodebuild -license accept
sudo xcodebuild -runFirstLaunch

say "Simulator runtimes (several GB each)"
xcrun simctl list runtimes | grep -q '^iOS' || xcodebuild -downloadPlatform iOS
xcrun simctl list runtimes | grep -q '^watchOS' || xcodebuild -downloadPlatform watchOS
xcrun simctl list runtimes

say "developer tools without a password prompt"
sudo DevToolsSecurity -enable
sudo dseditgroup -o edit -a "$(whoami)" -t user _developer

say "Homebrew and xcodegen"
if ! command -v brew >/dev/null; then
	NONINTERACTIVE=1 /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
	[ -x /opt/homebrew/bin/brew ] && eval "$(/opt/homebrew/bin/brew shellenv)"
	grep -q 'brew shellenv' ~/.zprofile 2>/dev/null || echo 'eval "$(/opt/homebrew/bin/brew shellenv)"' >>~/.zprofile
fi
brew install xcodegen

say "no sleep, no screen saver"
sudo pmset -a sleep 0 displaysleep 0 disksleep 0
defaults -currentHost write com.apple.screensaver idleTime 0

say "done"
echo "Next: in Safari here, open github.com/jeremybarnum/sportmode-sim/settings/actions/runners/new"
echo "(macOS, $(uname -m | sed 's/arm64/ARM64/; s/x86_64/x64/')), run its commands in Terminal, label bench-mac, then ./run.sh"
