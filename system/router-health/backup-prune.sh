#!/bin/sh
# backup-prune.sh - keep the router's backup areas bounded on the overlay.
#
# Two phases, run back to back in one invocation:
#   phase 1  /root/backup       (added 2026-11-01) - anchor dir, pattern rules
#   phase 2  /root/final-backup (original logic, unchanged) - dir-quota rules
#
# Phase 2 (/root/final-backup) policy (all limits overridable through the
# environment, for testing):
#   BACKUP_PRUNE_ROOT        root directory to prune   (default /root/final-backup)
#   BACKUP_PRUNE_KEEP        max number of newest child dirs to keep   (default 10)
#   BACKUP_PRUNE_MAX_KB      max total logical size of the root in KB   (default 512)
#   BACKUP_PRUNE_MIN_AGE_MIN do not delete dirs younger than this (min) (default 180)
#   BACKUP_PRUNE_LOG         append-only audit log                     (default /root/backup-prune.log)
#
# Phase 2 safety rules (hard-coded, not overridable):
#   * ONLY direct child directories of ROOT are ever considered.
#   * this phase touches /root/final-backup only; /root/backup has its own
#     phase 1 rules (anchor files are never auto-deleted there).
#   * symlinks and non-directories are never deleted.
#   * a directory whose mtime is younger than MIN_AGE_MIN is never deleted
#     (protects a backup that is being written right now).
#   * the single newest directory is never deleted.
#   * a directory containing a file named ".inprogress" is never deleted.
#   * names listed in $ROOT/.keep are never deleted.
#   * idempotent: a second run with no new backups deletes nothing more.
#
# Exit codes: 0 ok, 1 nothing to do / root missing, 2 busy (lock held).
# (phase 1 never exits on its own; the exit code always comes from phase 2.)

# ======================================================================
# phase 1: /root/backup  (added 2026-11-01; thresholds = docs/MAINTENANCE.md §3)
#
# Policy (overridable through the environment, for testing):
#   BACKUP_PRUNE_BROOT       root directory to prune    (default /root/backup)
#   BACKUP_PRUNE_BKEEP_PRE   how many newest pre-* dirs to keep (default 3)
#   BACKUP_PRUNE_BMAX_KB     max total size of the root in KB (default 1024 = 1 MiB)
#   BACKUP_PRUNE_BMIN_AGE    do not delete entries younger than this, min (default 180)
#   BACKUP_PRUNE_LOG         audit log, shared with phase 2 (default /root/backup-prune.log)
#
# Rules (same scheme as MAINTENANCE §3, no new inventiveness):
#   * *.bak-<timestamp> copies with the same stem: keep only the newest 1.
#   * pre-* DIRECTORIES: keep only the newest 3 (by mtime), delete the rest.
#   * *.apk-new: always delete (upstream default templates, no local value).
#   * total size over BMAX_KB: cull oldest unprotected loose files first.
#
# Never deleted (anchors / in-flight protection):
#   * sysupgrade.conf, luci-theme-argon-files.tar.gz,
#     final-25.12.6-config.tar.gz, uhttpd.key.orig, uhttpd.crt.orig,
#     wireless.keep11k
#   * the newest BKEEP_PRE pre-* directories
#   * anything listed in $BROOT/.keep (one name per line)
#   * a directory containing a file named ".inprogress"
#   * anything younger than BMIN_AGE_MIN (may still be written)
#   * symlinks, dot files, and unknown subdirectories - only the pattern
#     matches above and unprotected loose files are ever deleted; anything
#     else needs a human decision.
# ======================================================================

BROOT="${BACKUP_PRUNE_BROOT:-/root/backup}"
BLOG="${BACKUP_PRUNE_LOG:-/root/backup-prune.log}"
BKEEP_PRE="${BACKUP_PRUNE_BKEEP_PRE:-3}"
BSIZE_MAX_KB="${BACKUP_PRUNE_BMAX_KB:-1024}"
BMIN_AGE_MIN="${BACKUP_PRUNE_BMIN_AGE:-180}"
BK_ALWAYS="sysupgrade.conf luci-theme-argon-files.tar.gz final-25.12.6-config.tar.gz uhttpd.key.orig uhttpd.crt.orig wireless.keep11k"
LOCK_B="$BROOT/.prune.lock"
NOW_B=$(date +%s)
TMPD_B="/tmp/.backup-prune-b.$$"

log2() {
  echo "$*"
  [ -n "$BLOG" ] && echo "$*" >> "$BLOG" 2>/dev/null
  return 0
}

b_is_keep() {  # $1 = entry name; return 0 = protected, 1 = not protected
  local b_name b_k
  b_name="$1"
  for b_k in $BK_ALWAYS; do
    [ "$b_name" = "$b_k" ] && return 0
  done
  if [ -f "$BROOT/.keep" ] && grep -q "^$b_name\$" "$BROOT/.keep" 2>/dev/null; then
    return 0
  fi
  return 1
}

if [ -d "$BROOT" ]; then
  B_RUN=1
  if [ -e "$LOCK_B" ]; then
    LM_B=$(date -r "$LOCK_B" +%s 2>/dev/null || echo 0)
    if [ $(( NOW_B - LM_B )) -lt 1800 ]; then
      log2 "backup-prune: /root/backup: lock is fresh - another run in progress, skipping"
      B_RUN=0
    else
      log2 "backup-prune: /root/backup: removing stale lock"
      rm -f "$LOCK_B"
    fi
  fi
  if [ "$B_RUN" -eq 1 ]; then
    : > "$LOCK_B"
    trap 'rm -rf "$TMPD_B" 2>/dev/null; rm -f "$LOCK_B" 2>/dev/null' EXIT INT TERM
    mkdir -p "$TMPD_B"
    : > "$TMPD_B"/cand

    # ---- classify direct children (pattern rules + anchor check) ----
    B_ENTRIES=0
    for b_f in "$BROOT"/*; do
      [ -e "$b_f" ] || continue
      [ -L "$b_f" ] && continue
      B_ENTRIES=$((B_ENTRIES+1))
      b_n=$(basename "$b_f")
      b_is_keep "$b_n" && continue
      case "$b_n" in
        *.apk-new) echo "apk-new (upstream template, no local value)|$b_f" >> "$TMPD_B"/cand ;;
      esac
    done

    # ---- pre-* dirs: keep newest BKEEP_PRE, older = candidates ----
    : > "$TMPD_B"/pre
    for b_f in "$BROOT"/pre-*; do
      [ -d "$b_f" ] || continue
      [ -L "$b_f" ] && continue
      b_m=$(date -r "$b_f" +%s 2>/dev/null)
      case "$b_m" in ''|*[!0-9]*) b_m=$NOW_B ;; esac
      echo "$b_m $b_f"
    done | sort -rn > "$TMPD_B"/pre
    B_I=0
    while IFS= read -r b_line; do
      B_I=$((B_I+1))
      [ "$B_I" -le "$BKEEP_PRE" ] && continue
      echo "pre-* beyond the newest $BKEEP_PRE|${b_line#* }" >> "$TMPD_B"/cand
    done < "$TMPD_B"/pre

    # ---- *.bak-* files: same stem keeps only the newest 1 ----
    : > "$TMPD_B"/stems
    for b_f in "$BROOT"/*.bak-*; do
      [ -f "$b_f" ] || continue
      [ -L "$b_f" ] && continue
      b_n=$(basename "$b_f")
      echo "${b_n%%.bak-*}"
    done | sort -u > "$TMPD_B"/stems
    while IFS= read -r b_stem; do
      [ -n "$b_stem" ] || continue
      : > "$TMPD_B"/stemfiles
      for b_f in "$BROOT"/"$b_stem".bak-*; do
        [ -f "$b_f" ] || continue
        [ -L "$b_f" ] && continue
        b_m=$(date -r "$b_f" +%s 2>/dev/null)
        case "$b_m" in ''|*[!0-9]*) b_m=$NOW_B ;; esac
        echo "$b_m $b_f"
      done | sort -rn > "$TMPD_B"/stemfiles
      B_J=0
      while IFS= read -r b_line; do
        B_J=$((B_J+1))
        [ "$B_J" -le 1 ] && continue
        echo ".bak-* older than the newest 1 of stem $b_stem|${b_line#* }" >> "$TMPD_B"/cand
      done < "$TMPD_B"/stemfiles
    done < "$TMPD_B"/stems

    # ---- total size cap: cull oldest unprotected loose files first ----
    B_TOTAL_KB=$(du -sk "$BROOT" 2>/dev/null | cut -f1)
    [ -n "$B_TOTAL_KB" ] || B_TOTAL_KB=0
    if [ "$B_TOTAL_KB" -gt "$BSIZE_MAX_KB" ]; then
      log2 "backup-prune: /root/backup: total ${B_TOTAL_KB}KB > ${BSIZE_MAX_KB}KB - size-cap cull"
      : > "$TMPD_B"/loose
      for b_f in "$BROOT"/*; do
        [ -f "$b_f" ] || continue
        [ -L "$b_f" ] && continue
        b_n=$(basename "$b_f")
        b_is_keep "$b_n" && continue
        case "$b_n" in *.bak-*) continue ;; esac  # newest-1 per stem kept by rule
        b_m=$(date -r "$b_f" +%s 2>/dev/null)
        case "$b_m" in ''|*[!0-9]*) b_m=$NOW_B ;; esac
        echo "$b_m $b_f"
      done | sort -rn > "$TMPD_B"/loose
      while IFS= read -r b_line && [ "$B_TOTAL_KB" -gt "$BSIZE_MAX_KB" ]; do
        echo "size-cap (total > ${BSIZE_MAX_KB}KB)|${b_line#* }" >> "$TMPD_B"/cand
        b_sz=$(du -sk "${b_line#* }" 2>/dev/null | cut -f1)
        [ -n "$b_sz" ] || b_sz=0
        B_TOTAL_KB=$((B_TOTAL_KB - b_sz))
      done < "$TMPD_B"/loose
    fi

    # ---- apply candidates (anchors + .inprogress + min-age re-checked) ----
    B_DELETED=0
    B_KEPT=0
    B_FREED=0
    while IFS= read -r b_cl; do
      [ -n "$b_cl" ] || continue
      b_reason=${b_cl%%|*}
      b_path=${b_cl#*|}
      [ -e "$b_path" ] || continue
      b_n=$(basename "$b_path")
      if b_is_keep "$b_n"; then
        log2 "backup-prune: /root/backup: KEEP $b_n (protected name)"
        B_KEPT=$((B_KEPT+1))
        continue
      fi
      if [ -d "$b_path" ] && [ -e "$b_path/.inprogress" ]; then
        log2 "backup-prune: /root/backup: KEEP $b_n (.inprogress marker present)"
        B_KEPT=$((B_KEPT+1))
        continue
      fi
      b_m=$(date -r "$b_path" +%s 2>/dev/null)
      case "$b_m" in ''|*[!0-9]*) b_m=$NOW_B ;; esac
      b_age=$(( (NOW_B - b_m) / 60 ))
      if [ "$b_age" -lt "$BMIN_AGE_MIN" ]; then
        log2 "backup-prune: /root/backup: KEEP $b_n (age ${b_age}min < ${BMIN_AGE_MIN}min - may be in use)"
        B_KEPT=$((B_KEPT+1))
        continue
      fi
      b_sz=$(du -sk "$b_path" 2>/dev/null | cut -f1)
      [ -n "$b_sz" ] || b_sz=0
      rm -rf "$b_path"
      if [ -e "$b_path" ]; then
        log2 "backup-prune: /root/backup: FAILED to delete $b_n (still present)"
        continue
      fi
      B_DELETED=$((B_DELETED+1))
      B_FREED=$((B_FREED+b_sz))
      log2 "backup-prune: /root/backup: DELETED $b_n (${b_sz}KB, age ${b_age}min) - reason: $b_reason"
    done < "$TMPD_B"/cand

    B_FINAL_KB=$(du -sk "$BROOT" 2>/dev/null | cut -f1)
    log2 "backup-prune: /root/backup: done - entries=$B_ENTRIES deleted=$B_DELETED kept=$B_KEPT freed=${B_FREED}KB final=${B_FINAL_KB}KB (pre_keep=$BKEEP_PRE bak_keep=1 max_kb=$BSIZE_MAX_KB min_age=${BMIN_AGE_MIN}min)"
    if [ "$B_FINAL_KB" -gt "$BSIZE_MAX_KB" ]; then
      log2 "backup-prune: /root/backup: WARN still ${B_FINAL_KB}KB > ${BSIZE_MAX_KB}KB - unknown dirs are never auto-deleted, needs manual review"
    fi

    rm -rf "$TMPD_B"
    rm -f "$LOCK_B"
    trap - EXIT INT TERM
  fi
else
  log2 "backup-prune: /root/backup does not exist - skipping phase 1"
fi
unset BROOT BLOG BKEEP_PRE BSIZE_MAX_KB BMIN_AGE_MIN BK_ALWAYS LOCK_B NOW_B TMPD_B \
      B_RUN LM_B B_ENTRIES B_TOTAL_KB B_DELETED B_KEPT B_FREED B_FINAL_KB \
      B_I B_J b_f b_n b_m b_line b_stem b_cl b_reason b_path b_age b_sz b_k 2>/dev/null
unset -f log2 b_is_keep 2>/dev/null

# ======================================================================
# phase 2: /root/final-backup (original logic, byte-for-byte unchanged)
# ======================================================================

ROOT="${BACKUP_PRUNE_ROOT:-/root/final-backup}"
KEEP_MAX="${BACKUP_PRUNE_KEEP:-10}"
SIZE_MAX_KB="${BACKUP_PRUNE_MAX_KB:-512}"
MIN_AGE_MIN="${BACKUP_PRUNE_MIN_AGE_MIN:-180}"
LOGFILE="${BACKUP_PRUNE_LOG:-/root/backup-prune.log}"
LOCK="$ROOT/.prune.lock"
NOW=$(date +%s)

say() {
  echo "$*"
  if [ -n "$LOGFILE" ]; then
    echo "$*" >> "$LOGFILE" 2>/dev/null
  fi
}

[ -d "$ROOT" ] || { say "backup-prune: root $ROOT does not exist - nothing to do"; exit 1; }

# ---- lock (avoid two overlapping runs) ----
if [ -e "$LOCK" ]; then
  LM=$(date -r "$LOCK" +%s 2>/dev/null || echo 0)
  if [ $(( NOW - LM )) -lt 1800 ]; then
    say "backup-prune: lock $LOCK is fresh - another run is in progress, aborting"
    exit 2
  fi
  say "backup-prune: removing stale lock $LOCK"
  rm -f "$LOCK"
fi
: > "$LOCK"

TMPD="/tmp/.backup-prune.$$"
rm -rf "$TMPD"
mkdir -p "$TMPD" || { rm -f "$LOCK"; exit 1; }

cleanup() {
  rm -rf "$TMPD"
  rm -f "$LOCK"
}
trap cleanup EXIT INT TERM

# ---- collect direct child directories with their mtime ----
for d in "$ROOT"/*; do
  [ -d "$d" ] || continue
  [ -L "$d" ] && continue
  b=$(basename "$d")
  case "$b" in
    .*) continue ;;
  esac
  m=$(date -r "$d" +%s 2>/dev/null)
  case "$m" in
    ''|*[!0-9]*) m=$NOW ;;
  esac
  echo "$m $d"
done | sort -rn > "$TMPD"/new

TOTAL_ENTRIES=$(wc -l < "$TMPD"/new)
if [ "$TOTAL_ENTRIES" -eq 0 ]; then
  say "backup-prune: $ROOT has no child directory - nothing to do"
  exit 0
fi

# oldest-first view; rank 1 = newest, rank N = oldest
awk '{a[NR]=$0} END{for(i=NR;i>=1;i--) print i, a[i]}' "$TMPD"/new > "$TMPD"/old

TOTAL_KB=$(du -sk "$ROOT" 2>/dev/null | cut -f1)
[ -n "$TOTAL_KB" ] || TOTAL_KB=0

say "backup-prune: root=$ROOT entries=$TOTAL_ENTRIES total=${TOTAL_KB}KB keep_max=$KEEP_MAX max_kb=$SIZE_MAX_KB min_age=${MIN_AGE_MIN}min"

DELETED=0
KEPT=0
SKIPPED=0
FREED=0

while IFS= read -r line; do
  rank=${line%% *}
  rest=${line#* }
  mtime=${rest%% *}
  path=${rest#* }
  name=$(basename "$path")
  case "$rank$mtime" in
    *[!0-9]*) echo "backup-prune: SKIP malformed entry: $line"; continue ;;
  esac
  age_min=$(( (NOW - mtime) / 60 ))

  # never delete the newest entry
  if [ "$rank" -eq 1 ]; then
    KEPT=$((KEPT+1)); continue
  fi
  # never delete anything younger than MIN_AGE_MIN
  if [ "$age_min" -lt "$MIN_AGE_MIN" ]; then
    say "backup-prune: KEEP $name (age ${age_min}min < ${MIN_AGE_MIN}min - may be in use)"
    KEPT=$((KEPT+1)); continue
  fi
  # never delete a dir flagged as in-progress
  if [ -e "$path/.inprogress" ]; then
    say "backup-prune: KEEP $name (.inprogress marker present)"
    KEPT=$((KEPT+1)); continue
  fi
  # never delete a name listed in $ROOT/.keep
  if [ -f "$ROOT/.keep" ] && grep -q "^$name\$" "$ROOT/.keep" 2>/dev/null; then
    say "backup-prune: KEEP $name (listed in .keep)"
    KEPT=$((KEPT+1)); continue
  fi

  reason=""
  if [ "$rank" -gt "$KEEP_MAX" ]; then
    reason="older than the newest $KEEP_MAX"
  fi
  if [ "$TOTAL_KB" -gt "$SIZE_MAX_KB" ]; then
    reason="$reason total ${TOTAL_KB}KB > ${SIZE_MAX_KB}KB"
  fi
  reason=$(echo "$reason" | sed 's/^ *//')

  if [ -z "$reason" ]; then
    KEPT=$((KEPT+1)); continue
  fi

  SZ=$(du -sk "$path" 2>/dev/null | cut -f1)
  [ -n "$SZ" ] || SZ=0
  rm -rf "$path"
  if [ -d "$path" ]; then
    say "backup-prune: FAILED to delete $name (still present)"
    SKIPPED=$((SKIPPED+1)); continue
  fi
  DELETED=$((DELETED+1))
  FREED=$((FREED+SZ))
  TOTAL_KB=$((TOTAL_KB - SZ))
  say "backup-prune: DELETED $name (${SZ}KB, age ${age_min}min) - reason: $reason"
done < "$TMPD"/old

FINAL_KB=$(du -sk "$ROOT" 2>/dev/null | cut -f1)
say "backup-prune: done - deleted=$DELETED kept=$KEPT skipped=$SKIPPED freed=${FREED}KB final=${FINAL_KB}KB"

# keep the audit log bounded (overlay is small)
if [ -n "$LOGFILE" ] && [ -f "$LOGFILE" ]; then
  LSZ=$(wc -c < "$LOGFILE")
  if [ "$LSZ" -gt 16384 ]; then
    tail -n 50 "$LOGFILE" > "$TMPD"/log.new
    cat "$TMPD"/log.new > "$LOGFILE"
    say "backup-prune: audit log truncated to last 50 lines"
  fi
fi

exit 0
