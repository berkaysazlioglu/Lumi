#!/usr/bin/env bash
# RelayServer'ı Heroku'ya deploy eder (docs/design/09). Monorepo'nun yalnız bu
# klasörü geçici bir git deposuna kopyalanıp app'in git remote'una itilir —
# Lumi deposunda commit ya da subtree gerekmez.
#   APP=lumi-relay scripts/deploy-heroku.sh
set -euo pipefail

APP="${APP:-lumi-relay}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

rsync -a --exclude node_modules --exclude dist --exclude .git "$ROOT/" "$WORK/"
cd "$WORK"
git init -q -b main
git add -A
git -c user.name="lumi-deploy" -c user.email="deploy@localhost" commit -qm "deploy $(date -u +%Y-%m-%dT%H:%M:%SZ)"
git push -f "https://git.heroku.com/$APP.git" main
