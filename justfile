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
