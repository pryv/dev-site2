# add node bin script path for recipes
export PATH := "./node_modules/.bin:" + env_var('PATH')

# Default: display available recipes
_help:
    @just --list

# Install dependencies
setup:
    npm install

# Build the site from src/ into dist/
build *params:
    astro build {{params}}

# Dev server with live reload
dev *params:
    astro dev {{params}}

# Preview the built dist/
preview:
    astro preview

# Serve the built dist/ behind backloop.dev (never bare localhost)
serve:
    backloop.dev ./dist 4443

# Clean the build output
clean:
    rm -rf dist .astro

# Import the event-types catalogue from a data-types checkout (its committed dist/,
# assumed rebuilt from its src/):
#   public/event-types/flat.json         <- dist/flat.json         (the URL cores fetch)
#   public/event-types/hierarchical.json <- dist/event-types.json
#   src/data/event-types.json            <- dist/event-types.json  (the reference page)
# Copies, verifies each file byte for byte, and prints what was imported. It does not
# build, commit or publish. Publishing changes what every core validates against, and
# open-pryv.io vendors the catalogue with a drift check, so re-vendor there right after.
import-event-types data_types="../data-types":
    #!/usr/bin/env bash
    set -euo pipefail
    src={{quote(data_types)}}
    trap 'rm -f public/event-types/*.tmp src/data/*.tmp' EXIT
    git -C "$src" rev-parse --git-dir >/dev/null 2>&1 || { echo "$src is not a data-types git checkout"; exit 1; }
    [ -f "$src/dist/flat.json" ] && [ -f "$src/dist/event-types.json" ] || { echo "no built dist/ in $src (npm run build there first)"; exit 1; }
    if [ -n "$(git -C "$src" status --porcelain -- dist src)" ]; then
      echo "data-types has uncommitted changes in dist/ or src/: import a committed catalogue"; exit 1
    fi
    if ! git -C "$src" merge-base --is-ancestor HEAD origin/master 2>/dev/null; then
      echo "WARNING: $src HEAD is not contained in origin/master (feature branch or unpushed commits): publishing this import would put unmerged catalogue changes live"
    fi
    copy () {
      cp "$src/dist/$1" "$2.tmp" && mv "$2.tmp" "$2"
      cmp -s "$src/dist/$1" "$2" || { echo "copy mismatch: $2"; exit 1; }
    }
    copy flat.json public/event-types/flat.json
    copy event-types.json public/event-types/hierarchical.json
    copy event-types.json src/data/event-types.json
    node -e 'for (const f of process.argv.slice(1)) { const j = JSON.parse(require("fs").readFileSync(f, "utf8")); if (j === null || typeof j !== "object" || (j.types == null && j.classes == null)) throw new Error(f + ": not an event-types catalogue"); }' public/event-types/flat.json public/event-types/hierarchical.json src/data/event-types.json
    echo "Imported data-types $(git -C "$src" rev-parse --short HEAD) on $(git -C "$src" rev-parse --abbrev-ref HEAD) ($(node -e 'console.log(Object.keys(require(process.argv[1]).types).length)' "$PWD/public/event-types/flat.json") types)."
    git status --short -- public/event-types src/data/event-types.json

# Mirrors dist/ into a local checkout of pryv/pryv.github.io under .publish/ (gitignored),
# adds the required .nojekyll (the site has _astro/ underscore dirs that GitHub Pages'
# Jekyll step would otherwise drop), commits and pushes to master. Fresh ROOT build first
# (no SITE_BASE => base '', indexable robots.txt, no noindex). Nothing is committed HERE.
# Build the root site and push it live to https://pryv.github.io/ (org pages repo).
publish:
    #!/usr/bin/env bash
    set -euo pipefail
    pages_repo="git@github.com:pryv/pryv.github.io.git"
    work=".publish"
    # 1. fresh ROOT build (SITE_BASE unset so links resolve at '/')
    rm -rf dist .astro
    env -u SITE_BASE astro build
    # 2. ensure a clean checkout of the pages repo at origin/master
    if [ ! -d "$work/.git" ]; then rm -rf "$work"; git clone "$pages_repo" "$work"; fi
    git -C "$work" fetch origin
    git -C "$work" checkout -q master
    git -C "$work" reset --hard -q origin/master
    git -C "$work" clean -fdxq
    # 3. replace content (keep .git), copy fresh build, add .nojekyll
    find "$work" -mindepth 1 -maxdepth 1 ! -name .git -exec rm -rf {} +
    cp -R dist/. "$work"/
    touch "$work/.nojekyll"
    git -C "$work" add -A
    if git -C "$work" diff --cached --quiet; then echo "Nothing to publish."; exit 0; fi
    git -C "$work" commit -q -m "Rebuild developer site"
    git -C "$work" push origin master
    echo "Published to https://pryv.github.io/"

# Sets SITE_BASE so links resolve at the subpath and the integration writes a Disallow
# robots.txt + noindex meta. Deploy dist/ to the repo's gh-pages branch by hand (or via
# your pages workflow); nothing here pushes automatically.
# Build a noindex preview under a subpath (default /dev-site2) for pre-publish review.
build-preview base='/dev-site2':
    rm -rf dist .astro
    SITE_BASE={{base}} astro build
