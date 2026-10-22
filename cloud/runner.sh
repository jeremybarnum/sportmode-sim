#!/bin/sh
# Installs and starts the GitHub Actions runner for this repository on a Mac, labelled bench-mac, in
# ~/actions-runner. The one argument is the registration token GitHub shows on the repository's
# Settings, Actions, Runners, New self-hosted runner page (valid an hour). Run it in a Terminal
# window of the Mac's desktop session, and leave the window open: the runner runs in it.
#   curl -fsSL https://raw.githubusercontent.com/jeremybarnum/sportmode-sim/simlink-live/cloud/runner.sh | sh -s <token>
set -eu
token=${1:?usage: runner.sh <registration token>}
# The runner keeps the PATH it was configured with: xcodegen's home-folder install on it.
export PATH="$HOME/xcodegen/bin:$PATH"
command -v xcodegen >/dev/null || { echo "no xcodegen: run cloud/setup-mac.sh first"; exit 1; }
arch=$(uname -m | sed 's/x86_64/x64/')
v=$(curl -fsSL https://api.github.com/repos/actions/runner/releases/latest | sed -n 's/.*"tag_name": *"v\([^"]*\)".*/\1/p')
mkdir -p ~/actions-runner && cd ~/actions-runner
if [ ! -x ./config.sh ]; then
	echo "downloading runner $v ($arch)"
	curl -fsSL -o runner.tar.gz "https://github.com/actions/runner/releases/download/v$v/actions-runner-osx-$arch-$v.tar.gz"
	tar xzf runner.tar.gz && rm runner.tar.gz
fi
[ -f .runner ] || ./config.sh --unattended --url https://github.com/jeremybarnum/sportmode-sim --token "$token" \
	--labels bench-mac --name "bench-mac-$(hostname -s)" --work _work
exec ./run.sh
