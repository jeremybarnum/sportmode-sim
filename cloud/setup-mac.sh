#!/bin/sh
# Readies a rented Mac to run the bench as a GitHub self-hosted runner, after Xcode is installed:
# its licence and first launch, the iOS and watchOS Simulators, developer tools without a password
# prompt (the tap drivers), xcodegen, and no screen saver. With admin rights it does what needs them;
# without (a managed Mac, where these are usually done already) it checks them and installs xcodegen
# in the home folder. Then: register the runner (repository Settings, Actions, Runners, label
# bench-mac) from a new Terminal window, and ./run.sh it.
set -u
say() { printf '\n== %s\n' "$*"; }
admin=; id -Gn | tr ' ' '\n' | grep -qx admin && admin=1

say "this Mac"
sw_vers; uname -m; xcodebuild -version; df -h ~ | tail -1
echo "admin rights: ${admin:-no}"
[ -n "$admin" ] && { sudo -v || exit 1; }

say "Xcode: licence and first launch"
if [ -n "$admin" ]; then sudo xcodebuild -license accept; sudo xcodebuild -runFirstLaunch
else xcodebuild -checkFirstLaunchStatus && echo "first launch done" || echo "Xcode's first launch is not done: open Xcode once and let it install its components"; fi

say "Simulator runtimes (several GB each)"
xcrun simctl list runtimes | grep -q '^iOS' || xcodebuild -downloadPlatform iOS
xcrun simctl list runtimes | grep -q '^watchOS' || xcodebuild -downloadPlatform watchOS
xcrun simctl list runtimes

say "developer tools without a password prompt"
if [ -n "$admin" ]; then sudo DevToolsSecurity -enable; sudo dseditgroup -o edit -a "$(whoami)" -t user _developer
else DevToolsSecurity -status; fi

say "xcodegen"
if ! command -v xcodegen >/dev/null; then
	# Homebrew if this Mac has one this account can install with; else the release, in the home folder.
	if command -v brew >/dev/null && brew install xcodegen; then :
	else
		# The release's own build, in the home folder; its templates sit beside its binary.
		curl -fsSL -o /tmp/xcodegen.zip https://github.com/yonaskolb/XcodeGen/releases/latest/download/xcodegen.zip
		rm -rf ~/xcodegen && unzip -q /tmp/xcodegen.zip -d ~ && rm /tmp/xcodegen.zip
		grep -q 'xcodegen/bin' ~/.zprofile 2>/dev/null || echo 'export PATH="$HOME/xcodegen/bin:$PATH"' >>~/.zprofile
		grep -q 'xcodegen/bin' ~/.bash_profile 2>/dev/null || echo 'export PATH="$HOME/xcodegen/bin:$PATH"' >>~/.bash_profile
		export PATH="$HOME/xcodegen/bin:$PATH"
	fi
fi
xcodegen --version

say "no sleep, no screen saver"
[ -n "$admin" ] && sudo pmset -a sleep 0 displaysleep 0 disksleep 0
defaults -currentHost write com.apple.screensaver idleTime 0

say "done"
echo "Next: open a NEW Terminal window (so xcodegen is on its PATH), and in Safari here open"
echo "github.com/jeremybarnum/sportmode-sim/settings/actions/runners/new"
echo "(macOS, $(uname -m | sed 's/arm64/ARM64/; s/x86_64/x64/')); run its commands in that window, label bench-mac, then ./run.sh"
