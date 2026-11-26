#!/usr/bin/env bash
set -u
W={run-worktree}
. "$W/tests/fixtures.sh"
TMP_ROOT=$(fm_test_tmproot fmsbx-live2)
unset DISABLE_AUTOUPDATER TRACEPARENT LAVISH_AXI_HOST LAVISH_AXI_PORT
n=0
mk() { n=$((n+1)); C=$TMP_ROOT/c$n; H=$C/home; P=$C/project; WT=$C/wt
  FB=$(fm_test_make_spawn_fakebin "$C/fake" claude); printf '#!/usr/bin/env bash\necho FAKE_OMP\n' > "$FB/omp"; chmod +x "$FB/omp"
  fm_test_spawn_home "$H" omp; fm_git_worktree "$P" "$WT" "wt-$n"; fm_test_spawn_brief "$H" "$1"; }
sp() { FM_FAKE_LAUNCH_LOG=$C/launch.log FM_FAKE_PANE_LOG=$C/pane.log fm_test_run_spawn "$H" "$WT" "$FB" "$@"; echo "[exit=$?]"; }
res() { echo "  meta=$( [ -f $H/state/$1.meta ] && grep -E '^sandbox=' $H/state/$1.meta || echo '<no record>') wrapped=$(grep -c fmsbx-live/wrapper.sh $C/launch.log 2>/dev/null || echo 0) launched_bytes=$(wc -c < $C/launch.log 2>/dev/null || echo 0)"; }
echo "== A: no config/sandbox -> plain launch"; mk t-a; sp t-a "$P" --scout --harness omp | tail -1; res t-a; ls $H/state | grep -c sbx | sed 's/^/  sbx dirs=/'
echo "== B: --sandbox unknown profile under real wrapper -> refuse"; mk t-b; printf 'wrapper=/tmp/fmsbx-live/wrapper.sh\n' > $H/config/sandbox; sp t-b "$P" --scout --harness omp --sandbox bogus | tail -2; res t-b
echo "== C: mapped profile, wrapper missing -> refuse"; mk t-c; printf 'wrapper=/nonexistent/worker-sandbox\nkind:scout=lab-profile\n' > $H/config/sandbox; sp t-c "$P" --scout --harness omp | tail -2; res t-c
echo "== D: enforce=strict, --sandbox off -> refuse"; mk t-d; printf 'wrapper=/tmp/fmsbx-live/wrapper.sh\nenforce=strict\nkind:scout=lab-profile\n' > $H/config/sandbox; sp t-d "$P" --scout --harness omp --sandbox off | tail -2; res t-d
echo "== E: enforce=strict, unmapped scout -> refuse"; mk t-e; printf 'wrapper=/tmp/fmsbx-live/wrapper.sh\nenforce=strict\nkind:ship=lab-profile\n' > $H/config/sandbox; sp t-e "$P" --scout --harness omp | tail -2; res t-e
echo "== F: mapped profile, non-omp harness (claude) -> refuse"; mk t-f; printf 'wrapper=/tmp/fmsbx-live/wrapper.sh\nkind:scout=lab-profile\n' > $H/config/sandbox; sp t-f "$P" --scout --harness claude | tail -2; res t-f
echo "== G: enforce=on, --sandbox off -> waived, recorded off"; mk t-g; printf 'wrapper=/tmp/fmsbx-live/wrapper.sh\nkind:scout=lab-profile\n' > $H/config/sandbox; sp t-g "$P" --scout --harness omp --sandbox off | tail -1; res t-g
echo "== H: mapped spawn then --relaunch re-wraps from meta"; mk t-h; printf 'wrapper=/tmp/fmsbx-live/wrapper.sh\nkind:scout=lab-profile\n' > $H/config/sandbox; sp t-h "$P" --scout --harness omp | tail -1; res t-h
g1=$(grep -o "relay-helper" $C/launch.log | head -1); gen1=$(cat $H/state/t-h.busy-gen 2>/dev/null)
: > $C/launch.log; sp t-h "$P" --scout --harness omp --relaunch | tail -1; res t-h; gen2=$(cat $H/state/t-h.busy-gen 2>/dev/null); echo "  gen changed: $([ "$gen1" != "$gen2" ] && echo yes || echo no) helper-in-relaunch=$(grep -c 'sbx/relay-helper' $C/launch.log)"
echo "   relaunch with another profile:"; : > $C/launch.log; sp t-h "$P" --scout --harness omp --relaunch --sandbox other | tail -2
echo "== I: teardown removes the spool"; ls -d $H/state/t-h.sbx && FM_HOME=$H FM_STATE_OVERRIDE=$H/state FM_DATA_OVERRIDE=$H/data FM_CONFIG_OVERRIDE=$H/config FM_PROJECTS_OVERRIDE=$H/projects FM_ROOT_OVERRIDE='' PATH="$FB:$PATH" TMUX=fake,1,0 $W/bin/fm-teardown.sh t-h --force 2>&1 | tail -2; echo "  sbx after teardown: $([ -e $H/state/t-h.sbx ] && echo PRESENT || echo removed)"
