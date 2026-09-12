# syntax = docker/dockerfile:1
# docs-kit Dockerfile v1.1.1 — regenerate/diff: bin/rails g docs_kit:install
#
# The docs app depends on the gem via `gem "importmap-plus", path: ".."`, so the
# build context is the REPO ROOT (not docs/): the gem lives at /app and the docs
# app at /app/docs. Build with `docker build -f docs/Dockerfile .` from the repo
# root, or via dash's builder `context: ..` + `dockerfile: Dockerfile`. The
# repo-root .dockerignore keeps that context small.
#
# A lean, multi-stage production image: the final stage carries only the runtime
# (Ruby + the installed bundle + the app), never the build toolchain
# (build-essential, git, bun) — those live in the throwaway `build` stage.

ARG RUBY_VERSION=3.4.2
FROM docker.io/library/ruby:$RUBY_VERSION-slim AS base

WORKDIR /app/docs

# Keep in step with the repo-root .bun-version: bun.lock is written by the local
# bun, and an older bun can't read a newer lockfile version.
ARG BUN_VERSION=1.4.0
ENV BUN_INSTALL="/usr/local/bun" \
    PATH="/usr/local/bun/bin:$PATH" \
    BUNDLE_DEPLOYMENT="0" \
    BUNDLE_PATH="/usr/local/bundle" \
    BUNDLE_WITHOUT="development:test" \
    BUNDLE_GEMFILE="/app/docs/Gemfile" \
    RAILS_ENV="production"

# Base packages the RUNTIME needs (jemalloc for a smaller/faster heap, curl for
# the container healthcheck). Anything only the build needs goes in `build`.
RUN apt-get update -qq && \
    apt-get install --no-install-recommends -y curl libjemalloc2 && \
    rm -rf /var/lib/apt/lists /var/cache/apt/archives


# --- Build stage (throwaway — its layers never reach the final image) ---------
FROM base AS build

# Toolchain to compile native gems + fetch bun. Skip the apt cleanup: this whole
# stage is discarded.
RUN apt-get update -qq && \
    apt-get install --no-install-recommends -y build-essential git libyaml-dev pkg-config unzip
RUN curl -fsSL https://bun.sh/install | bash -s -- "bun-v${BUN_VERSION}"

# Copy the WHOLE repo (gem at /app, docs app at /app/docs): the gem is a path
# dependency, so it has to be present before bundle install resolves it.
COPY . /app/

# Frozen off: the path-gem's digest can't be pinned across commits; the lockfile
# still pins every other gem. Prune the bundler cache + any git-sourced gem
# checkouts so they don't bloat the layer the final stage copies.
RUN bundle config set frozen false && bundle install && \
    rm -rf ~/.bundle/ "${BUNDLE_PATH}"/ruby/*/cache "${BUNDLE_PATH}"/ruby/*/bundler/gems/*/.git

# JS deps (the Tailwind/daisyUI CLI), then assets:precompile — enhanced by the
# css:build rake task so it runs `bun run build:css` before propshaft
# fingerprints. Drop node_modules + the bun cache afterwards — the built CSS is
# all we keep.
RUN bun install --frozen-lockfile
RUN SECRET_KEY_BASE_DUMMY=1 ./bin/rails assets:precompile && \
    rm -rf node_modules .bun tmp/cache


# --- Final stage --------------------------------------------------------------
FROM base

# dash's validate_image greps this label on a --skip-push deploy; it must equal
# `service:` in config/deploy.yml. The reusable deploy workflow also stamps it,
# but keeping it here means `docker build` alone produces a dash-valid image.
LABEL service="importmap-plus"

# Copy ONLY the built artifacts from the build stage: the installed bundle and
# the repo (with precompiled assets). No toolchain, no node_modules.
COPY --from=build "${BUNDLE_PATH}" "${BUNDLE_PATH}"
COPY --from=build /app /app

# Run as a non-root user; own only the runtime dirs it writes.
RUN groupadd --system --gid 1000 rails && \
    useradd rails --uid 1000 --gid 1000 --create-home --shell /bin/bash && \
    chown -R 1000:1000 /app/docs/log /app/docs/tmp
USER 1000:1000

# libjemalloc2 (installed in `base`) only takes effect when preloaded; the
# builder is amd64 (config/deploy.yml), so the path is fixed.
ENV LD_PRELOAD="/usr/lib/x86_64-linux-gnu/libjemalloc.so.2"

EXPOSE 3000
# Thruster fronts Puma (HTTP caching + compression + X-Sendfile). It listens on
# HTTP_PORT and proxies to Puma on TARGET_PORT (it sets PORT for the child, which
# config/puma.rb reads). HTTP_PORT MUST be the port traffic is routed to (dash's
# `app_port`, the EXPOSE above) — Thruster's default is 80, which the non-root
# user can't reliably bind AND which dash-proxy (app_port: 3000) would never
# route to, silently bypassing Thruster straight into Puma.
ENV HTTP_PORT="3000" \
    TARGET_PORT="3001"
CMD ["./bin/thrust", "./bin/rails", "server"]
