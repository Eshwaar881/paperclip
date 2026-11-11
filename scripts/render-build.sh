#!/usr/bin/env bash
# render-build.sh — Full production build for Render.com deployment.
#
# Build order:
#   1. shared       — types, validators, constants
#   2. db           — schema + migrations (compiled, not migrated here)
#   3. runner       — TypeScript only (no Rust; Render is linux-x64 but we skip
#                     the native binary to keep build times reasonable and because
#                     the runner binary is not required for the control-plane API)
#   4. plugin-sdk   — bundled plugin SDK
#   5. ui           — Vite production build
#   6. server       — tsc + copies ui-dist + writes build stamp
#
# After this script, Render starts the server with:
#   node server/dist/index.js
# which connects to DATABASE_URL (Render managed PostgreSQL) and auto-migrates
# on first boot via migratePostgresIfEmpty().

set -euo pipefail

export NODE_OPTIONS="${NODE_OPTIONS:-} --max-old-space-size=3072"
export PAPERCLIP_TSC_EMIT_ONLY=1
export PAPERCLIP_TYPECHECK_LOW_MEMORY=1

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT"

echo "==> Installing dependencies..."
pnpm install --frozen-lockfile

echo ""
echo "==> Generating ACPX profiles..."
pnpm --filter @paperclipai/paperclip-runner generate:acpx-profiles

echo ""
echo "==> Generating protocol types..."
pnpm --filter @paperclipai/paperclip-runner generate:protocol-types

echo ""
echo "==> Building @paperclipai/shared..."
pnpm --filter @paperclipai/shared build

echo ""
echo "==> Building @paperclipai/db..."
pnpm --filter @paperclipai/db build

echo ""
echo "==> Building @paperclipai/adapter-utils..."
pnpm --filter @paperclipai/adapter-utils build

echo ""
echo "==> Building @paperclipai/paperclip-runner (TypeScript only)..."
pnpm --filter @paperclipai/paperclip-runner build:typescript

echo ""
echo "==> Building @paperclipai/plugin-sdk..."
pnpm --filter @paperclipai/plugin-sdk build

echo ""
echo "==> Building UI (Vite)..."
pnpm --filter @paperclipai/ui build

echo ""
echo "==> Building @paperclipai/server (includes copying ui-dist)..."
# PAPERCLIP_RELEASE_REUSE_UI_DIST=1 tells prepare-server-ui-dist.sh to reuse
# the ui/dist we just built above instead of rebuilding it.
# PAPERCLIP_SKIP_RUNNER_VENDOR_REBUILD=1 reuses the runner TypeScript build we
# just completed above instead of trying to run `cargo build` on Render.
PAPERCLIP_RELEASE_REUSE_UI_DIST=1 PAPERCLIP_SKIP_RUNNER_VENDOR_REBUILD=1 pnpm --filter @paperclipai/server build

echo ""
echo "==> Build complete."
echo "    Start command: node server/dist/index.js"

