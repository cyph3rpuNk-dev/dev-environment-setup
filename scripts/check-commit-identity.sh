#!/usr/bin/env bash
# Fail when any commit reachable from REV credits someone other than the allowed
# identities, or carries a co-author, session-link or tool attribution line.
#
#   ALLOWED_EMAILS="you@users.noreply.github.com" bash scripts/check-commit-identity.sh [REV]
#
# Identity is checked by email, which is what GitHub uses to link a commit to an
# account. Merges made on GitHub's website are committed by GitHub itself, so that
# committer is accepted; their author must still be an allowed email.
set -euo pipefail
for dependency in git grep; do
  command -v "$dependency" >/dev/null 2>&1 || {
    echo "FAIL required command unavailable: $dependency" >&2
    exit 1
  }
done
rev=${1:-HEAD}
allowed=${ALLOWED_EMAILS:?set ALLOWED_EMAILS to the permitted author emails}
web_committer=noreply@github.com

is_allowed() { case " $allowed " in *" $1 "*) return 0 ;; esac; return 1; }

checked=0
failures=0
while IFS= read -r sha; do
  checked=$((checked + 1))
  author_email=$(git log -1 --format=%ae "$sha")
  committer_email=$(git log -1 --format=%ce "$sha")
  label="${sha:0:7} $(git log -1 --format=%s "$sha")"
  if ! is_allowed "$author_email"; then
    echo "FAIL $label: author $(git log -1 --format='%an <%ae>' "$sha") is not allowed"
    failures=$((failures + 1))
  fi
  if ! is_allowed "$committer_email" && [ "$committer_email" != "$web_committer" ]; then
    echo "FAIL $label: committer $(git log -1 --format='%cn <%ce>' "$sha") is not allowed"
    failures=$((failures + 1))
  fi
  if git log -1 --format=%B "$sha" | grep -qiE '^[[:space:]]*(co-authored-by|[a-z0-9_-]+-session|generated-by):|^[[:space:]]*generated (with|by)[[:space:]]'; then
    echo "FAIL $label: message contains a co-author or attribution line"
    failures=$((failures + 1))
  fi
done < <(git rev-list "$rev")

if [ "$checked" -eq 0 ]; then echo "FAIL no commits found for $rev"; exit 1; fi
if [ "$failures" -gt 0 ]; then echo "$failures problem(s) in $checked commit(s)"; exit 1; fi
echo "ok: $checked commit(s) credit only the allowed identity"
