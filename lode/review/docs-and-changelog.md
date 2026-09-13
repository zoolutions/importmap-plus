What the docs site and CHANGELOG must keep saying, and how the docs app itself is wired.

### The pin-comment grammar on the Provenance page lists `not an ES module` among the `remote:` reasons
- **Holds because:** the Grammar section is what someone editing a pin by hand reads, and the reason list has to be the set the code can actually write: `ModuleInspector::PATTERNS`' five keys (`relative imports`, `dynamic imports`, `workers`, `import.meta.url`, `wasm`) plus the `"not an ES module"` string `pin_vendored_package` passes for `NotAnEsModule`. A reason missing from the list reads as a typo the user should "fix", which would drop the provenance on the next rewrite.
- **Where:** `docs/app/views/docs/pages/provenance.rb#grammar` (and `#the_comment`); mirrors `lib/importmap/commands.rb#pin_vendored_package` and `lib/importmap/module_inspector.rb#PATTERNS`
- **Proven by:** `test/commands_test.rb:"pin keeps a package remote when the CDN hands back something that isn't an ES module"` pins the string the docs must match; the docs page itself is covered only by `docs/spec/requests/docs_spec.rb:"renders the provenance page"` (render, not content)
- **Origin:** cubic learning e95aa367

### The custom-minifier hook is documented as an assignment in `config/application.rb`, not in a Rails initializer
- **Holds because:** `bin/importmap` loads `config/application.rb` but not the app's initializers, so `Importmap::Packager.minifier = …` placed in an initializer never runs for the CLI and `--minify` silently falls back to whatever bun/esbuild/terser is on PATH. The docs code sample carries `filename: "config/application.rb"` and says "or in a file it requires".
- **Where:** `docs/app/views/docs/pages/minifying.rb#custom_minifier`; the hook is `lib/importmap/packager.rb#self.minifier`
- **Proven by:** no test
- **Origin:** cubic learning 83bd804d

### The CHANGELOG says `pristine` never converts an already-vendored pin; only the next `pin` or `update` that touches one does
- **Holds because:** the conversion is real behaviour — a pre-check vendored pin whose file can't stand alone becomes a remote pin — and users need it described as the fix arriving rather than as a surprise. Claiming `pristine` rewrites those pins would contradict the code (`pristine` downloads with `force: true`) and send people looking for a change that never happens.
- **Where:** `CHANGELOG.md` (1.2.0 "pin keeps a package remote when its file can't stand alone"); `docs/app/views/docs/pages/pinning.rb#cant_be_vendored_alone`; behaviour in `lib/importmap/commands.rb#pristine`
- **Proven by:** `test/commands_test.rb:"pristine command skips packages pinned to remote URLs"` (the post-conversion half); the CHANGELOG text itself has no test
- **Origin:** PR #22

### Docs, CHANGELOG and the code comments all describe a default import of a no-exports module as a link-time failure in the browser, not a silent `undefined`
- **Holds because:** a UMD bundle loaded through an import map runs and exports nothing, and `import x from "pkg"` then throws `The requested module does not provide an export named 'default'` — a link-time `SyntaxError` that takes down every module that imported it, and only in the browser. Describing it as "x is undefined" sends the reader looking for a runtime bug in their own code instead of at the pin.
- **Where:** `CHANGELOG.md` ("A download that isn't an ES module is kept remote instead of vendored"); `docs/app/views/docs/pages/upgrading.rb#what_changes`; `docs/app/views/docs/pages/pinning.rb`; comments on `lib/importmap/packager.rb#NotAnEsModule` and `lib/importmap/module_inspector.rb#es_module?`
- **Proven by:** no test
- **Origin:** PR #24

### The docs app's `lint` task globs both `lib/**/*.rb` and `lib/**/*.rake`
- **Holds because:** the file list is passed to RuboCop explicitly so the nested app is linted regardless of the gem's own RuboCop excludes — and the docs app's `lib/` holds rake tasks (`build_css.rake`, `docs_kit_og.rake`), not just Ruby files. Dropping the `.rake` glob leaves them unlinted while CI still reports green.
- **Where:** `docs/Rakefile` (`lint_files`, used by `lint` and `lint:fix`)
- **Proven by:** no test; enforced by `.github/workflows/docs-ci.yml` running `bundle exec rake lint`
- **Origin:** cubic learning 59c94672

### A throttled docs request gets a `Retry-After` computed from the time left in the current Rack::Attack bucket
- **Holds because:** Rack::Attack buckets by `epoch_time / period`, so the window ends at the next multiple of `period` — returning the whole period tells a client to wait longer than it has to, on every single 429. The responder reads `match_data[:period]` and `match_data[:epoch_time]` and returns `period - (epoch_time % period)` in both the header and the body.
- **Where:** `docs/config/initializers/rack_attack.rb` (`Rack::Attack.throttled_responder`)
- **Proven by:** no test
- **Origin:** cubic learning 227c1986

### The provenance grammar is written in six places and every one matches `Packager#provenance_comment`'s token order
- **Holds because:** the comment is `# @<version> (<provider>[, minified][, vendored][, remote[: <reason>]][, locked])`, lock always last (`packager.rb:48-49`, `test/packager_test.rb` "locked_pin_line puts the lock last"). The grammar is stated in `CLAUDE.md` (the Never-Do rule and the pin-line contract), `lode/summary.md`, `lode/terminology.md`, `lode/packager/summary.md`, `lode/docs-site/summary.md` and `docs/app/views/docs/pages/provenance.rb`. The first gate on the seeding branch found it stated three different ways; a reader who trusts the wrong one writes a pin `PIN_PROVENANCE_REGEXP` still reads but `rewrite_provenance` re-emits reordered, which looks like an unexplained diff on the next `update`.
- **Where:** `lib/importmap/packager.rb#provenance_comment`; the six files above
- **Proven by:** `test/packager_test.rb:"locked_pin_line puts the lock last"` for the order; the prose has no test — grep `vendored\]\[, remote` across `CLAUDE.md lode docs` before changing it
- **Origin:** gate on chore/lode, 2026-09-13
