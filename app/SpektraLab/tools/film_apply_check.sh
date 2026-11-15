#!/bin/bash
# film_apply_check.sh -- Apply Film over a selection in the running app (Sources/Mac/LibraryUI/
# MacFilmApplyCheck.swift): the emulsion alone moves and each picture keeps the rest of its own,
# previews develop again, one step of history names the film, Undo takes a frame back on a page and
# off one, the film a frame already has says so and makes nothing, and a picture never opened has its
# frame made with the film on it. A run under a minute means nothing developed (trap 26).
#
# The check's report is $out/report.json; the run's log $out/run.log. A Debug build first
# (tools/build_engine_mac.sh, gen_project.py, xcodebuild --configuration Debug).
#
# Exit 0 when the check passes.
set -euo pipefail
here=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
out="$here/build/film-apply-check"; app="$here/build/DerivedData/Build/Products/Debug-maccatalyst/SpektraLab.app"; keep=0
while [[ $# -gt 0 ]]; do
  case "$1" in
    --out) out=$2; shift 2 ;;
    --app) app=$2; shift 2 ;;
    --keep) keep=1; shift ;;
    *) echo "unknown: $1"; exit 2 ;;
  esac
done
bin="$app/Contents/MacOS/SpektraLab"
[[ -x "$bin" ]] || { echo "no app at $app (build Debug first)"; exit 2; }
# A copy with a bundle identifier of this run's own: the build's preferences are never reachable (tools/check_app.sh).
source "$here/tools/check_app.sh"; check_app_isolate "$app"
home=$(mktemp -d "${TMPDIR:-/tmp}/film-apply-check-home.XXXXXX")
suite="spk.film-apply-check.$(basename "$home")"
rm -rf "$out"; mkdir -p "$out" "$home/in"
# Three pictures of the check's own, copied (a develop writes to the library, never the source):
# the same scene three times, for the check tells them apart by their frames, not their pixels.
cp "$here/SampleSources/scene_raw_srgb.jpg" "$home/in/1.jpg"
cp "$here/SampleSources/scene_raw_srgb.jpg" "$home/in/2.jpg"
cp "$here/SampleSources/scene_raw_srgb.jpg" "$home/in/3.jpg"
start=$(date +%s)
set +e
CFFIXED_USER_HOME="$home" "$bin" --library real --defaults-suite "$suite" --film-apply-check "$out" \
  --film-apply-check-files "$home/in/1.jpg" "$home/in/2.jpg" "$home/in/3.jpg" \
  --library-check-exit > "$out/run.log" 2>&1
s=$?
set -e
echo "ran $(( $(date +%s) - start )) s, exit $s"
grep -h "^film-apply-check:" "$out/run.log" || true
defaults delete "$suite" > /dev/null 2>&1 || true
rm -f "$HOME/Library/Preferences/$suite.plist"
if [[ $keep -eq 1 ]]; then echo "home kept: $home"; else rm -rf "$home"; fi
[[ $s -eq 0 ]]
