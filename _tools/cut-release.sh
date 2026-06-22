#!/usr/bin/env bash
set -euo pipefail

# cut-release.sh — build every platform `tsgo` binary, package each as a gzip, and
# create a GitHub release on effect-app/tsgo carrying them plus a SHA256SUMS file.
#
# This is the manual release path for the effect-app fork: the upstream `release.yml`
# only runs for `Effect-TS`-owned repos on a changeset merge, so fork binaries are cut
# from here. The produced assets are exactly what consumers download via
# scripts/install-patched-compilers.mjs:
#   tsgo-<platform>-<arch>.gz            (e.g. tsgo-linux-x64.gz)
#   tsgo-win32-<arch>.exe.gz             (windows)
#   SHA256SUMS                           (`<sha256>  <asset>` per line)
#
# The version is derived from source so the tag, release title and the binary's own
# `--version` can never drift:
#   core base : typescript-go/internal/core/version.go   ->  7.0.0-dev
#   suffix    : etscheckerhooks/init.go SetVersionSuffix  ->  effect-app.6
#   => title  'tsgo 7.0.0-dev+effect-app.6'   tag 'v7.0.0-dev-effect-app.6'
# Bump the suffix in etscheckerhooks/init.go before cutting a new release.
#
# Usage:
#   cut-release.sh [--repo <owner/name>] [--skip-setup] [--dry-run] [--notes <text>]
#     --repo        Target repository (default: effect-app/tsgo)
#     --skip-setup  Skip `pnpm setup-repo` (reuse the already-patched submodule tree)
#     --dry-run     Build + package, print the release command, but do not publish
#     --notes       Override the release notes body

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$REPO_ROOT"

REPO="effect-app/tsgo"
DRY_RUN=false
SKIP_SETUP=false
NOTES=""
while [ $# -gt 0 ]; do
  case "$1" in
    --repo) REPO="$2"; shift 2 ;;
    --skip-setup) SKIP_SETUP=true; shift ;;
    --dry-run) DRY_RUN=true; shift ;;
    --notes) NOTES="$2"; shift 2 ;;
    *) echo "ERROR: unknown flag '$1'"; exit 1 ;;
  esac
done

# ── Derive version from source ────────────────────────────────────────────────
core_base="$(sed -nE 's/.*var version = "([^"]+)".*/\1/p' typescript-go/internal/core/version.go | head -1)"
suffix="$(sed -nE 's/.*SetVersionSuffix\("\+(effect-app\.[0-9]+)"\).*/\1/p' etscheckerhooks/init.go | head -1)"
if [ -z "$core_base" ] || [ -z "$suffix" ]; then
  echo "ERROR: could not derive version (core_base='$core_base' suffix='$suffix')"
  exit 1
fi
full_version="${core_base}+${suffix}"
tag="v${core_base}-${suffix}"
title="tsgo ${full_version}"
echo "==> Cutting ${title} (tag ${tag}) on ${REPO}"

# npm platform-arch identifiers, matching install-patched-compilers.mjs asset names.
TARGETS=(darwin-arm64 darwin-x64 win32-x64 win32-arm64 linux-x64 linux-arm64 linux-arm)

# ── Build ─────────────────────────────────────────────────────────────────────
if [ "$SKIP_SETUP" != true ]; then
  echo "==> Applying patches (pnpm setup-repo --ci)"
  pnpm setup-repo --ci
fi
echo "==> Cross-compiling ${#TARGETS[@]} targets"
pnpm release:prepare --skip-cli

# ── Package gz assets + checksums ─────────────────────────────────────────────
STAGE="$(mktemp -d)"
trap 'rm -rf "$STAGE"' EXIT
assets=()
for t in "${TARGETS[@]}"; do
  bin="tsgo"; gz="tsgo-${t}.gz"
  case "$t" in win32-*) bin="tsgo.exe"; gz="tsgo-${t}.exe.gz" ;; esac
  src="_packages/tsgo-${t}/lib/${bin}"
  [ -s "$src" ] || { echo "ERROR: missing built binary $src"; exit 1; }
  gzip -c -9 "$src" > "$STAGE/$gz"
  assets+=("$STAGE/$gz")
done
( cd "$STAGE" && sha256sum tsgo-*.gz > SHA256SUMS )
assets+=("$STAGE/SHA256SUMS")
echo "==> Packaged assets:"
( cd "$STAGE" && ls -la && echo "--- SHA256SUMS ---" && cat SHA256SUMS )

# ── Sanity check: the host-platform binary reports the derived version ─────────
host_os="$(go env GOOS)"; host_arch="$(go env GOARCH)"
case "${host_os}-${host_arch}" in
  darwin-arm64) host_id=darwin-arm64 ;; darwin-amd64) host_id=darwin-x64 ;;
  linux-amd64)  host_id=linux-x64    ;; linux-arm64)  host_id=linux-arm64 ;;
  *) host_id="" ;;
esac
if [ -n "$host_id" ]; then
  reported="$("_packages/tsgo-${host_id}/lib/tsgo" --version 2>/dev/null | awk '{print $2}')"
  if [ "$reported" != "$full_version" ]; then
    echo "ERROR: built binary reports '$reported', expected '$full_version' (bump etscheckerhooks/init.go?)"
    exit 1
  fi
  echo "==> Host binary version OK: $reported"
fi

if [ -z "$NOTES" ]; then
  NOTES="Effect language-service tsgo + .d.ts schema-facade emit (${full_version}). Built from PR #1."
fi

if [ "$DRY_RUN" = true ]; then
  echo "==> DRY RUN — would run:"
  echo "    gh release create $tag --repo $REPO --title \"$title\" ${assets[*]}"
  exit 0
fi

# ── Publish ───────────────────────────────────────────────────────────────────
if gh release view "$tag" --repo "$REPO" >/dev/null 2>&1; then
  echo "==> Release $tag exists — uploading/overwriting assets"
  gh release upload "$tag" --repo "$REPO" --clobber "${assets[@]}"
else
  gh release create "$tag" --repo "$REPO" --title "$title" --notes "$NOTES" "${assets[@]}"
fi
echo "==> Released: https://github.com/${REPO}/releases/tag/${tag}"
