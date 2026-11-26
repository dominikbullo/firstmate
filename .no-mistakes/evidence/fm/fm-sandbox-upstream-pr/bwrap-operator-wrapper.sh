#!/usr/bin/env bash
# Operator-supplied bubblewrap wrapper implementing the firstmate wrapper contract.
set -u
log=${SBX_LOG:-/dev/null}
{ printf 'CALL'; for a in "$@"; do printf ' [%s]' "$a"; done; printf '\n'; } >> "$log"
profile= wt= helper= dry=0; binds=(); envs=()
while [ $# -gt 0 ]; do
  case "$1" in
    --profile) profile=$2; shift 2;;
    --worktree) wt=$2; binds+=(--bind "$2" "$2"); shift 2;;
    --ro) binds+=(--ro-bind "$2" "$2"); shift 2;;
    --rw) binds+=(--bind "$2" "$2"); shift 2;;
    --rw-create) [ -e "$2" ] || : > "$2"; binds+=(--bind "$2" "$2"); shift 2;;
    --env) envs+=("$2"); shift 2;;
    --host-helper) helper=$2; shift 2;;
    --dry-run) dry=1; shift;;
    --) shift; break;;
    *) echo "wrapper: unknown option $1" >&2; exit 2;;
  esac
done
[ "$profile" = lab-profile ] || { echo "wrapper: unknown profile $profile" >&2; exit 2; }
[ -x "$helper" ] || { echo "wrapper: host helper not executable" >&2; exit 2; }
[ -n "$wt" ] || { echo "wrapper: --worktree required" >&2; exit 2; }
[ "$dry" = 0 ] || exit 0
"$helper" & hp=$!
sys=(); extra=(); for x in ${SBX_EXTRA_RO:-}; do extra+=(--ro-bind "$x" "$x"); done; for d in /nix /etc /usr /bin /lib /lib64 /run/current-system /etc/profiles; do [ -e "$d" ] && sys+=(--ro-bind "$d" "$d"); done
bwrap "${sys[@]}" --proc /proc --dev /dev --tmpfs /tmp --tmpfs /home --tmpfs /run/user \
  --dir /tmp/probe-home --setenv HOME /tmp/probe-home \
  "${extra[@]}" "${binds[@]}" --chdir "$wt" -- bash -c '[ -n "${SBX_PROBE:-}" ] && bash "$SBX_PROBE"; exec "$@"' sbx "$@"
rc=$?
kill -TERM "$hp" 2>/dev/null; wait "$hp" 2>/dev/null
exit $rc
