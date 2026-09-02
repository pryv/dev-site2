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

# NOTE: the `publish` recipe (push built output to the org pages repo) is added
# at cutover, see the deploy design ruling. No built output is committed here.
