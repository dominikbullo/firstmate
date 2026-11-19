#!/usr/bin/env bash
set -u
cd "{run-worktree}/tests"
head -n 771 "{run-worktree}/tests/fm-spawn-sandbox.test.sh" | sed 's#^\. "$(dirname "${BASH_SOURCE\[0\]}")/fixtures.sh"#. "{run-worktree}/tests/fixtures.sh"#' > /tmp/fmsbx-live/funcs.sh
. /tmp/fmsbx-live/funcs.sh
L=/tmp/fmsbx-live; W={run-worktree}
id=sbx-live-a1
read_case "$(make_case live "$id")"
echo "CASE=$CASE_DIR HOME=$HOME_DIR WT=$WT_DIR STATE=$STATE_DIR FAKEBIN=$FAKEBIN_DIR"
# a victim task the sandboxed worker must not see
printf 'kind=ship\n' > "$STATE_DIR/victim-a1.meta"; printf 'secret-steer\n' > "$STATE_DIR/victim-a1.inbox"
sed "s#\$FAKEBIN_RO#$FAKEBIN_DIR#" $L/bwrap-wrapper > "$CASE_DIR/bwrap-wrapper"; chmod +x "$CASE_DIR/bwrap-wrapper"
# probing fake agent (stands in for the omp binary; spawn, wrapper, bwrap, relay are real)
cat > "$FAKEBIN_DIR/omp" <<EOF
#!/usr/bin/env bash
case "\${1:-}" in models) echo '{"models":[]}'; exit 0;; esac
echo "PROBE task=\${FM_TASK_ID:-unset} inbox=\${FM_TASK_INBOX:-unset} comp=\${COMPACT_ADVISER_DISABLE:-unset}"
echo "PROBE pwd=\$(pwd)"
[ -e "$STATE_DIR/victim-a1.meta" ] && echo "PROBE victim-meta VISIBLE" || echo "PROBE victim-meta hidden"
ls "$STATE_DIR" >/dev/null 2>&1 && echo "PROBE state-list: \$(ls "$STATE_DIR" | tr '\n' ' ')" || echo "PROBE state-dir unlistable"
touch "$STATE_DIR/escape" 2>/dev/null && echo "PROBE state WRITABLE" || echo "PROBE state write denied"
touch "$HOME_DIR/config/escape" 2>/dev/null && echo "PROBE fmhome WRITABLE" || echo "PROBE fmhome write denied"
echo working > "$STATE_DIR/$id.status" && echo "PROBE own status writable"
cat "\$FM_TASK_INBOX" >/dev/null 2>&1 && echo "PROBE own inbox readable"
echo note > "$HOME_DIR/data/$id/probe.txt" && echo "PROBE own data writable"
touch "$W/bin/escape" 2>/dev/null && echo "PROBE coderoot WRITABLE" || echo "PROBE coderoot bin read-only"
ls "$HOME_DIR/projects" >/dev/null 2>&1 && echo "PROBE projects VISIBLE" || echo "PROBE projects hidden"
ev="$STATE_DIR/$id.sbx/events"
printf '{"state":"busy","event":"live-probe"}' > "\$ev/.1.tmp" && mv "\$ev/.1.tmp" "\$ev/1.json" && echo "PROBE busy event spooled"
sleep 3
printf '{"state":"idle","event":"live-done"}' > "\$ev/.2.tmp" && mv "\$ev/.2.tmp" "\$ev/2.json" && echo "PROBE idle event spooled"
sleep 3
echo PROBE-END
EOF
chmod +x "$FAKEBIN_DIR/omp"
printf '%s\n' "wrapper=$CASE_DIR/bwrap-wrapper" 'project:project=strict' > "$HOME_DIR/config/sandbox"
out=$(run_spawn "$id" "$PROJ_DIR" --scout --harness omp); echo "SPAWN status=$? out=$out"
echo "META sandbox=$(sed -n 's/^sandbox=//p' "$STATE_DIR/$id.meta")"
printf '%s' "$CASE_DIR" > $L/case
E=~/.no-mistakes/evidence/01M7SAEG4Q5985EFNXAN3D8K22
cp "$LAUNCH_LOG" "$E/live-launch-text.txt"
TX=$L/tmux; mkdir -p $TX
T() { env -u TMUX TMUX_TMPDIR=$TX tmux -L fm-lab "$@"; }
T new-session -d -s primary -x 200 -y 50 -c "$WT_DIR" "env -u TMUX FAKEBIN_RO=$FAKEBIN_DIR BWRAP_WRAPPER_LOG=$CASE_DIR/wrapper.log bash --norc --noprofile"
sleep 1
while IFS= read -r ln; do T send-keys -t primary -l "$ln"; T send-keys -t primary Enter; sleep 0.2; done < "$LAUNCH_LOG"
for i in $(seq 1 40); do T capture-pane -p -t primary -S -200 | grep -q PROBE-END && break; sleep 0.5; done
sleep 2
T capture-pane -p -t primary -S -200 > "$E/live-pane-capture.txt"
T kill-server
echo "--- pane"; grep -E 'PROBE|rror|denied' "$E/live-pane-capture.txt"
echo "--- busy record"; ls "$STATE_DIR" | grep "$id"; cat "$STATE_DIR/$id.busy" 2>/dev/null || cat "$STATE_DIR"/$id.busy* 2>/dev/null
echo "--- relay.log"; cat "$STATE_DIR/$id.sbx/relay.log" 2>/dev/null
echo "--- wrapper.log"; cat "$CASE_DIR/wrapper.log"
echo "--- escape files on host"; ls -la "$STATE_DIR/escape" "$HOME_DIR/config/escape" "$W/bin/escape" 2>&1
echo "--- status"; cat "$STATE_DIR/$id.status"; cat "$HOME_DIR/data/$id/probe.txt"
echo "--- relay processes"; pgrep -af fm-sandbox-relay || echo none
