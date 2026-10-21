#!/bin/sh
# Makes a LoopWorkspace checkout of a Sport Mode branch testable in the Simulators: checks out the
# superproject branch to test (or keeps the current one), then applies the Simulator-only aids as
# local commits on a branch named sim-testing in the superproject and each changed submodule. Nothing
# is pushed, and nothing of the aids reaches a device build.
#
#   ./tree.sh [--aids <set>] <LoopWorkspace checkout> [superproject branch]
#   WORKSPACE=<checkout> ./tree.sh [--aids <set>] [superproject branch]
#
# The branch is fetched from the checkout's origin. The aids are the patches in aids/<set>/ (default
# next-dev; prod-126 for the production line), applied by file name order to the submodule each name
# starts with, plus the build flags and lines in aids/<set>/xcconfig added to LoopConfigOverride.xcconfig.
# A patch whose change the branch already has is skipped. Then: WORKSPACE=<checkout> ./sim.sh apps.
set -eu
here=$(cd "$(dirname "$0")" && pwd)

set_name=next-dev
if [ "${1:-}" = --aids ]; then set_name=$2; shift 2; fi
if [ -n "${WORKSPACE:-}" ]; then ws=$WORKSPACE; else ws=${1:?usage: tree.sh [--aids <set>] <LoopWorkspace checkout> [branch]}; shift; fi
branch=${1:-}
aids=$here/aids/$set_name
[ -d "$aids" ] || { echo "no aids set $set_name (aids/: $(ls "$here/aids" | tr '\n' ' '))" >&2; exit 2; }
cd "$ws"
[ -d LoopWorkspace.xcworkspace ] || { echo "$ws is not a LoopWorkspace checkout" >&2; exit 2; }
[ -z "$(git status --porcelain --ignore-submodules=all)" ] || { echo "$ws has uncommitted changes: commit or set them aside first" >&2; exit 2; }

# Commits made here carry the checkout's own git identity, or a stand-in when it has none.
g() {
	if [ -n "$(git config user.name 2>/dev/null)" ]; then git "$@"
	else git -c user.name="Simulator testing" -c user.email="sim-testing@localhost" "$@"; fi
}

if [ -n "$branch" ]; then
	git fetch -q origin "$branch"
	git checkout -q -B sim-testing FETCH_HEAD
else
	git checkout -q -B sim-testing
fi
git submodule update -q --init --recursive
echo "workspace at $(git log --oneline -1 | cut -c1-100)"

changed=
for patch in "$aids"/*.patch; do
	[ -e "$patch" ] || continue
	case "$(basename "$patch")" in
	loop-*) m=Loop ;;
	loopkit-*) m=LoopKit ;;
	omnipodkit-*) m=OmnipodKit ;;
	*) echo "$(basename "$patch"): name it after its submodule (loop-, loopkit-, omnipodkit-)" >&2; exit 2 ;;
	esac
	subject=$(sed -n 's/^Subject: \[PATCH\] //p' "$patch" | head -1)
	[ "$(git -C "$m" rev-parse --abbrev-ref HEAD)" = sim-testing ] || git -C "$m" checkout -q -B sim-testing
	if git -C "$m" apply --check -R "$patch" 2>/dev/null; then
		echo "$m: has \"$subject\""
	elif (cd "$m" && g am -q --3way "$patch"); then
		echo "$m: + \"$subject\""; changed="$changed $m"
	else
		(cd "$m" && git am --abort) 2>/dev/null || true
		echo "$m: \"$subject\" does not apply to this branch; the aid needs a version for it" >&2; exit 1
	fi
done

# Build flags and lines for LoopConfigOverride.xcconfig: "conditions: A B" adds compilation conditions,
# any other line is added as it is.
if [ -f "$aids/xcconfig" ]; then
	while IFS= read -r line; do
		case "$line" in
		""|"#"*) ;;
		conditions:*)
			for c in ${line#conditions:}; do
				grep -q "^SWIFT_ACTIVE_COMPILATION_CONDITIONS.* $c\( \|$\)" LoopConfigOverride.xcconfig ||
					sed -i '' "s/^\(SWIFT_ACTIVE_COMPILATION_CONDITIONS = \$(inherited)\)/\1 $c/" LoopConfigOverride.xcconfig
			done ;;
		*) grep -qxF "$line" LoopConfigOverride.xcconfig || printf '%s\n' "$line" >>LoopConfigOverride.xcconfig ;;
		esac
	done <"$aids/xcconfig"
fi

git add LoopConfigOverride.xcconfig $changed
if git diff --cached --quiet; then echo "nothing to commit: the tree already has the aids"
else
	g commit -q -m "Simulator testing of ${branch:-the current branch}: the Simulator-only aids ($set_name)"
	git log --oneline -1 | cut -c1-100
fi
echo "next: WORKSPACE=$ws ./sim.sh apps"
