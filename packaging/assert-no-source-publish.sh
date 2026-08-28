#!/usr/bin/env bash
# Refuse publishing paths that look like client *source* (not signed kits).
# Used by publish-*.sh before any gh release upload.
#
# Allowed: kit-*.tar.gz(+.minisig/.sha256), *-ui-*.tar.gz, RELEASE-SHA256SUMS*,
#          manifest-*.json(+.minisig), SHA256SUMS*, install scripts (never via this helper).
set -euo pipefail

deny_patterns=(
  '\.rs$'
  'Cargo\.(toml|lock)$'
  '/src/'
  '/src-tauri/'
  'client-wpplugin'
  'client-desktop'
  'wptsall-client/source'
  'node_modules'
  '\.git/'
)

for path in "$@"; do
  [ -e "$path" ] || continue
  if [ -d "$path" ]; then
    while IFS= read -r -d '' f; do
      "$0" "$f" || exit $?
    done < <(find "$path" -type f -print0)
    continue
  fi
  base="$(basename "$path")"
  # Explicit allow for release artifacts
  case "$base" in
    kit-*.tar.gz|kit-*.tar.gz.minisig|kit-*.tar.gz.sha256) continue ;;
    *-ui-*.tar.gz|*-ui-*.tar.gz.minisig|*-ui-*.tar.gz.sha256) continue ;;
    wptsall-client-*.tar.gz|wptsall-client-*.tar.gz.minisig) continue ;;
    wptsall-client-*.deb|wptsall-client-*.AppImage|wptsall-client-*.dmg|wptsall-client-*.exe|wptsall-client-*.msi) continue ;;
    RELEASE-SHA256SUMS*|SHA256SUMS*|manifest-*.json|manifest-*.json.minisig) continue ;;
  esac
  for re in "${deny_patterns[@]}"; do
    if printf '%s' "$path" | grep -Eq "$re"; then
      echo "REFUSE: will not publish source-like path: $path" >&2
      echo "Public releases must be signed kits / UI bundles / SUMS / manifest only." >&2
      exit 3
    fi
  done
  echo "REFUSE: unrecognized publish path (not in allowlist): $path" >&2
  exit 3
done
