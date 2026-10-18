#!/usr/bin/env bash
# Stage outcomes only; no raw output or credentials. Bash 3.2 compatible.
SETUP_ROWS="" SETUP_STAGE="" SETUP_STAGE_STATUS=completed SETUP_COMPLETED=0
complete_setup_stage() {
  [ -z "$SETUP_STAGE" ] || SETUP_ROWS="$SETUP_ROWS$SETUP_STAGE$(printf '\t')$SETUP_STAGE_STATUS
"
}
start_setup_stage() {
  # Avoid normalization subprocesses on ordinary runs without a receipt.
  [ -n "$RESULT_FILE" ] || return 0
  complete_setup_stage
  SETUP_STAGE=$(printf '%s' "$1" | tr '[:upper:]' '[:lower:]' | sed 's/[^a-z0-9][^a-z0-9]*/-/g;s/^-//;s/-$//')
  SETUP_STAGE_STATUS=completed
}
write_setup_receipt() {
  local result="$1" status=completed
  [ "$result" = 0 ] || status=failed-or-interrupted
  [ "$SETUP_COMPLETED" = 1 ] || SETUP_STAGE_STATUS=interrupted
  complete_setup_stage
  # Noclobber refuses an existing file; receipts are never executable resume input.
  if ! (set -C; printf '# devsetup-results-v1\nrun\t%s-%s\nstatus\t%s\n%s' "$(date -u +%Y%m%dT%H%M%SZ)" "$$" "$status" "$SETUP_ROWS" > "$RESULT_FILE"); then
    echo 'Could not create setup receipt; destination was preserved.' >&2; return 1
  fi
}
