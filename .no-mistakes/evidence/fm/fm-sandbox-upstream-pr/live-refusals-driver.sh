#!/usr/bin/env bash
set -u
cd "{run-worktree}/tests"
head -n 771 "{run-worktree}/tests/fm-spawn-sandbox.test.sh" | sed 's#^\. "$(dirname "${BASH_SOURCE\[0\]}")/fixtures.sh"#. "{run-worktree}/tests/fixtures.sh"#' > /tmp/fmsbx-live/funcs.sh
. /tmp/fmsbx-live/funcs.sh
L=/tmp/fmsbx-live; W={run-worktree}
id=sbx-live-a1
read_case "$(make_case live "$id")"
echo "CASE=$CASE_DIR HOME=$HOME_DIR WT=$WT_DIR STATE=$STATE_DIR FAKEBIN=$FAKEBIN_DIR"
L=/tmp/fmsbx-live
try() { # <label> <id> <config-lines|-> <spawn args...>
  local label=$1 id=$2 cfg=$3; shift 3
  read_case "$(make_case "$id" "$id")"
  cp $L/bwrap-wrapper "$CASE_DIR/bwrap-wrapper"
  if [ "$cfg" != - ]; then printf '%b\n' "${cfg//WRAP/$CASE_DIR/bwrap-wrapper}" > "$HOME_DIR/config/sandbox"; fi
  out=$(run_spawn "$id" "$PROJ_DIR" "$@"); st=$?
  [ -e "$STATE_DIR/$id.meta" ] && rec="record sandbox=$(sed -n 's/^sandbox=//p' "$STATE_DIR/$id.meta")" || rec="no record"
  grep -q bwrap-wrapper "$LAUNCH_LOG" && w=wrapped || { [ -s "$LAUNCH_LOG" ] && w="launched plain" || w="nothing launched"; }
  printf '== %s\n   exit=%s  %s  %s\n   %s\n' "$label" "$st" "$rec" "$w" "$(printf '%s' "$out" | grep -iE 'error|refus|spawned' | head -2 | tr '\n' ' ')"
}
try "no config/sandbox (default)" sbx-r1 - --scout --harness omp
try "enforce=off kill switch" sbx-r2 'wrapper=WRAP\nenforce=off\nproject:project=strict' --scout --harness omp
try "unknown profile rejected by real wrapper --dry-run" sbx-r3 'wrapper=WRAP\nproject:project=bogus' --scout --harness omp
try "missing wrapper binary" sbx-r4 'wrapper=/nonexistent/worker-sandbox\nproject:project=strict' --scout --harness omp
try "explicit --sandbox with no wrapper line" sbx-r5 'enforce=on' --scout --harness omp --sandbox strict
try "non-omp harness (claude) mapped" sbx-r6 'wrapper=WRAP\nproject:project=strict' --scout --harness claude
try "strict: unmapped scout" sbx-r7 'wrapper=WRAP\nenforce=strict' --scout --harness omp
try "strict: --sandbox off" sbx-r8 'wrapper=WRAP\nenforce=strict\nproject:project=strict' --scout --harness omp --sandbox off
try "on: --sandbox off waiver" sbx-r9 'wrapper=WRAP\nenforce=on\nproject:project=strict' --scout --harness omp --sandbox off
try "malformed config" sbx-r10 'wrapper=WRAP\nproject:project = strict' --scout --harness omp
# relaunch re-wraps with recorded profile
read_case "$(make_case rel sbx-rel1)"; cp $L/bwrap-wrapper "$CASE_DIR/bwrap-wrapper"
printf '%s\n' "wrapper=$CASE_DIR/bwrap-wrapper" 'project:project=strict' > "$HOME_DIR/config/sandbox"
run_spawn sbx-rel1 "$PROJ_DIR" --scout --harness omp >/dev/null; g1=$(cat "$STATE_DIR/sbx-rel1.busy-gen")
out=$(run_spawn sbx-rel1 --relaunch); st=$?
g2=$(cat "$STATE_DIR/sbx-rel1.busy-gen" 2>/dev/null)
grep -q "'--profile' 'strict'" "$LAUNCH_LOG" && w="re-wrapped with profile strict" || w="NOT wrapped"
grep -q -- "--gen '$g2'" "$STATE_DIR/sbx-rel1.sbx/relay-helper" && h="helper pins fresh gen" || h="helper gen mismatch"
printf '== relaunch of sandbox=strict task\n   exit=%s %s; gen %s -> %s; %s\n   %s\n' "$st" "$w" "$g1" "$g2" "$h" "$(printf '%s' "$out" | tail -1)"
