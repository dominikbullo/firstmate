#!/usr/bin/env bash
set -u
W={run-worktree}
. "$W/tests/fixtures.sh"
TMP_ROOT=$(fm_test_tmproot fmsbx-live)
echo "TMP_ROOT=$TMP_ROOT"
make_fake_omp() { cat > "$1/omp" <<'X'
#!/usr/bin/env bash
case "${1:-}" in models) printf '%s\n' '{"models":[]}' ;; *) printf 'FAKE_OMP_RAN task=%s inbox=%s\n' "${FM_TASK_ID:-unset}" "${FM_TASK_INBOX:-unset}" ;; esac
X
chmod +x "$1/omp"; }
case_dir=$TMP_ROOT/c; home=$case_dir/home; proj=$case_dir/project; wt=$case_dir/wt
fakebin=$(fm_test_make_spawn_fakebin "$case_dir/fake" claude); make_fake_omp "$fakebin"
fm_test_spawn_home "$home" omp
fm_git_worktree "$proj" "$wt" "wt-live"
id=live-scout
fm_test_spawn_brief "$home" "$id"
# an unrelated task's secret record the sandbox must not see
echo 'SECRET-OTHER' > "$home/state/other-task.inbox"; echo 'brief' > "$home/data/other-brief.md"
printf '%s\n' "wrapper=/tmp/fmsbx-live/wrapper.sh" "enforce=on" "kind:scout=lab-profile" > "$home/config/sandbox"
export SBX_LOG=$case_dir/wrapper.log
unset DISABLE_AUTOUPDATER TRACEPARENT LAVISH_AXI_HOST LAVISH_AXI_PORT
FM_FAKE_LAUNCH_LOG=$case_dir/launch.log FM_FAKE_PANE_LOG=$case_dir/pane.log fm_test_run_spawn "$home" "$wt" "$fakebin" "$id" "$proj" --scout --harness omp
echo "spawn exit=$?"
echo "--- meta sandbox field"; grep '^sandbox=' "$home/state/$id.meta"
echo "--- wrapper calls"; cat "$SBX_LOG"
echo "--- launch.log"; cat "$case_dir/launch.log"; echo; echo "--- pane.log"; head -c 1500 "$case_dir/pane.log"; echo
cp "$case_dir/launch.log" "$case_dir/launch.sh"
cat > "$wt/.probe.sh" <<P
echo "PROBE begin uid=\$(id -u) task=\${FM_TASK_ID:-unset}"
echo "PROBE ls-state: \$(ls '$home/state' 2>&1 | tr '\n' ' ')"
echo "PROBE other-inbox: \$(cat '$home/state/other-task.inbox' 2>&1)"
echo "PROBE other-data: \$(cat '$home/data/other-brief.md' 2>&1)"
echo "PROBE meta: \$(cat '$home/state/live-scout.meta' 2>&1 | head -1)"
echo "PROBE config: \$(ls '$home/config' 2>&1)"
echo "PROBE real-home: \$(ls ~ 2>&1 | head -1)"
echo "PROBE write-status: \$(echo working > '$home/state/live-scout.status' && echo ok)"
echo "PROBE write-state-dir: \$(touch '$home/state/evil' 2>&1 || true)"
echo "PROBE write-bin: \$(touch '$W/bin/evil' 2>&1 || true)"
echo "PROBE write-worktree: \$(touch '$wt/.sbx-ok' && echo ok)"
ev='$home/state/live-scout.sbx/events'
printf '{"state":"busy","event":"turn_start"}' > "\$ev/.t" && mv "\$ev/.t" "\$ev/1.json" && echo "PROBE spooled busy edge"
sleep 3
P
echo "--- host busy-state before:"; cat "$home/state/live-scout.busy-state"; echo
export TMUX_TMPDIR=$case_dir/tmux; mkdir -p "$TMUX_TMPDIR"
tmux -L fm-lab new-session -d -s primary -x 200 -y 50 -c "$wt" bash --norc
tmux -L fm-lab send-keys -t primary "export GOTMPDIR=/tmp/fm-live-scout/gotmp COMPACT_ADVISER_DISABLE=1 FM_TASK_ID=live-scout SBX_PROBE='$wt/.probe.sh' SBX_EXTRA_RO='$fakebin' SBX_LOG='$SBX_LOG'; . '$case_dir/launch.sh'; echo LAUNCH_DONE" Enter
for i in $(seq 1 30); do sleep 1; tmux -L fm-lab capture-pane -p -t primary | grep -q '^LAUNCH_DONE' && break; done
echo "--- pane capture"; tmux -L fm-lab capture-pane -p -J -t primary | grep -v '^$'
echo "--- host busy-state after:"; cat "$home/state/live-scout.busy-state"; echo
echo "--- relay.log:"; cat "$home/state/live-scout.sbx/relay.log" 2>&1
echo "--- host status file:"; cat "$home/state/live-scout.status"
echo "--- leftover host files: evil-state=$([ -e $home/state/evil ] && echo PRESENT || echo absent) evil-bin=$([ -e $W/bin/evil ] && echo PRESENT || echo absent) wt-write=$([ -e $wt/.sbx-ok ] && echo present)"
echo "--- relay processes still alive: $(pgrep -f "fm-sandbox-relay.sh run.*$id" | wc -l)"
tmux -L fm-lab kill-server
# teardown path removes the spool
