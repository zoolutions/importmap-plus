CI, release and deploy wiring — the supply-chain and trigger rules the workflows encode.

### `docs-ci.yml` filters on the gem inputs the docs site loads, in both `push` and `pull_request`
- **Holds because:** the docs app bundles the gem through `path: ".."`, renders the root `CHANGELOG.md` and reads the root `.bun-version`, so a change to `app/**`, `lib/**`, `importmap-plus.gemspec`, `CHANGELOG.md` or `.bun-version` can break the docs build while touching nothing under `docs/**`. With the filter narrowed to `docs/**` that break lands on `main` unnoticed. Both trigger blocks carry the same list — a path present in one and missing from the other means the PR is green and the push red, or vice versa.
- **Where:** `.github/workflows/docs-ci.yml` (`on.push.paths`, `on.pull_request.paths`)
- **Proven by:** no test
- **Origin:** cubic learning 9ef59b1e

### `release.yml`'s `workflow_dispatch` requires an explicit `tag` input
- **Holds because:** the push job runs in the `rubygems` environment with `id-token: write` and can mint a RubyGems token. Defaulting a manual run to "the latest release" makes the published artifact depend on repository state at click time rather than on something the operator named. `inputs.tag` is `required: true`, and `env.RELEASE_TAG` is `github.event.inputs.tag || github.ref_name`, so both entry points name a tag; a later step then fails the run unless that tag matches `Importmap::VERSION`.
- **Where:** `.github/workflows/release.yml` (`on.workflow_dispatch.inputs.tag`, `env.RELEASE_TAG`, the "Verify the tag matches Importmap::VERSION" step)
- **Proven by:** no test
- **Origin:** cubic learning 36f384e5

### Every action in `release.yml` is pinned to a reviewed commit SHA, with the version only as a trailing comment
- **Holds because:** the push job can mint a RubyGems token over OIDC, so a moving tag (`@v4`, `@v1`) that someone re-points runs different code with that privilege. All five `uses:` lines carry a 40-char SHA — `actions/checkout`, `ruby/setup-ruby` (twice each) and `rubygems/release-gem` — and the `# v4.4.0`-style tags beside them are readability hints only. The non-privileged workflows (`ci.yml`, `docs-ci.yml`) deliberately stay on tags.
- **Where:** `.github/workflows/release.yml` (all `uses:` lines)
- **Proven by:** no test
- **Origin:** cubic learning 2dcfde1f

### `deploy-docs.yml` pins the reusable docs-kit workflow to a reviewed commit SHA
- **Holds because:** the call hands that workflow `packages: write` and every inherited secret, so `@main` would let an unreviewed docs-kit change use them. The `uses:` names a SHA with a dated bump comment, and the file records how to bump it deliberately (`gh api repos/zoolutions/docs-kit/commits/main --jq .sha`).
- **Where:** `.github/workflows/deploy-docs.yml` (`jobs.deploy.uses`, `permissions`, `secrets: inherit`)
- **Proven by:** no test
- **Origin:** cubic learning 231d242b

### `docs/Dockerfile` takes bun from its official image pinned by digest, with the version tag alongside for readability
- **Holds because:** the alternative — `curl https://bun.sh/install | bash` — runs a mutable remote script as root during the build, and a bare `oven/bun:1.4.0-slim` tag can be re-pushed. The `FROM` carries both `${BUN_VERSION}-slim` and `@sha256:…`, so the digest decides what is pulled and the tag says what it is. `ARG BUN_VERSION` is kept in step with the repo-root `.bun-version` because `bun.lock` is written by the local bun and an older bun can't read a newer lockfile.
- **Where:** `docs/Dockerfile` (`ARG BUN_VERSION`, the `FROM docker.io/oven/bun:… AS bun` stage)
- **Proven by:** no test
- **Origin:** cubic learning 24f7fcf3

### A conflict in `lib/importmap/version.rb` takes the higher `VERSION` only when a commit in the range explains the bump
- **Holds because:** `VERSION` moves either in a feature PR that opens a new minor or in `bin/release` — never twice for one release. Taking the higher number reflexively double-bumps a release, and the `docs/Gemfile.lock` pin then drifts from a version that was never tagged. Check `git log <base>..HEAD -- lib/importmap/version.rb` for a commit that says why; with no such commit, keep the base version and ask. `UPSTREAM_VERSION` is the separate case: only a sync PR moves it, and it names the importmap-rails release merged in.
- **Where:** `lib/importmap/version.rb` (`VERSION`, `UPSTREAM_VERSION`); consumed by `.github/workflows/release.yml`'s tag check and `docs/Gemfile.lock`
- **Proven by:** no test; the release workflow's "Verify the tag matches Importmap::VERSION" step catches only the mismatch, not the double bump
- **Origin:** cubic learning 2a4acc35
