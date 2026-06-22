#!/usr/bin/env bash
#
# report.sh — structured logging + change tracking.
#
# Replaces the ad-hoc REPORT-string pattern matching that let a
# settings.json-only change slip past the "did anything change?" check
# (the *merged* gap in claude-code/setup.sh). Callers record outcomes
# through lw_record_change / lw_record_skip; lw_changed_p answers the
# commit-prompt question without grepping human-readable strings.
#
# stdout is reserved for function return values, so all log output goes
# to stderr.

lw_info() { printf '%s\n' "$*" >&2; }
lw_warn() { printf 'warning: %s\n' "$*" >&2; }

# Print to stderr and exit non-zero. The ONLY function in the library
# permitted to exit; everything else returns status so callers stay in
# control.
lw_die() { printf 'error: %s\n' "$*" >&2; exit 1; }

_LW_CHANGES=()
_LW_SKIPS=()

# Record a mutation that happened (file written, hook merged, block
# injected). The label is free text for the human-facing report only;
# the change-detection logic never parses it.
lw_record_change() { _LW_CHANGES+=("$1"); lw_info " + $1"; }

# Record a no-op (already present, already up to date).
lw_record_skip() { _LW_SKIPS+=("$1"); lw_info " . $1"; }

# True iff at least one change was recorded this run.
lw_changed_p() { [[ ${#_LW_CHANGES[@]} -gt 0 ]]; }

# Emit the accumulated report on stdout. The ${arr[@]+...} guards keep
# empty-array expansion safe under `set -u` on bash 3.2 (macOS system bash).
lw_print_report() {
  local line
  for line in ${_LW_SKIPS[@]+"${_LW_SKIPS[@]}"};   do printf ' . %s\n' "$line"; done
  for line in ${_LW_CHANGES[@]+"${_LW_CHANGES[@]}"}; do printf ' + %s\n' "$line"; done
}
