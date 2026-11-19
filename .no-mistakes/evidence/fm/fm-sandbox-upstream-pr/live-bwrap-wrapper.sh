#!/usr/bin/env bash
# Disposable real bubblewrap wrapper implementing the firstmate wrapper contract.
set -u
profile= wt= helper= dry=0; binds=(); envs=()
while [ $# -gt 0 ]; do
  case "$1" in
    --profile) profile=$2; shift 2 ;;
    --worktree) wt=$2; shift 2 ;;
    --ro) binds+=(--ro-bind "$2" "$2"); shift 2 ;;
    --rw) binds+=(--bind "$2" "$2"); shift 2 ;;
    --rw-create) [ -e "$2" ] || : > "$2"; binds+=(--bind "$2" "$2"); shift 2 ;;
    --env) envs+=("$2"); shift 2 ;;
    --host-helper) helper=$2; shift 2 ;;
    --dry-run) dry=1; shift ;;
    --) shift; break ;;
    *) echo "bwrap-wrapper: unknown option $1" >&2; exit 2 ;;
  esac
done
case "$profile" in strict) ;; *) echo "bwrap-wrapper: unknown profile $profile" >&2; exit 2 ;; esac
[ -n "$helper" ] || { echo "bwrap-wrapper: --host-helper required" >&2; exit 2; }
[ "$dry" = 0 ] || exit 0
echo "$(date +%s) profile=$profile wt=$wt helper=$helper envs=${envs[*]}" >> "${BWRAP_WRAPPER_LOG:-/dev/null}"
"$helper" & hp=$!
setenv=(--clearenv --setenv PATH "$PATH" --setenv HOME /tmp/sbxhome)
for n in "${envs[@]}"; do [ -n "${!n+x}" ] && setenv+=(--setenv "$n" "${!n}"); done
bwrap --unshare-pid --die-with-parent \
  --ro-bind /nix /nix --ro-bind /etc /etc --ro-bind /run/current-system /run/current-system \
  --ro-bind-try /etc/profiles /etc/profiles --ro-bind-try /bin /bin --ro-bind-try /usr /usr \
  --proc /proc --dev /dev --tmpfs /tmp --dir /tmp/sbxhome \
  --ro-bind "$FAKEBIN_RO" "$FAKEBIN_RO" \
  --bind "$wt" "$wt" "${binds[@]}" "${setenv[@]}" -- "$@"
rc=$?
kill -TERM "$hp" 2>/dev/null; wait "$hp" 2>/dev/null
exit $rc
