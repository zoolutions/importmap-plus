# Testing Rules

## TDD workflow

RED → GREEN → REFACTOR, always:

1. **RED** — write a failing Minitest and run it; watch it fail for the right reason
2. **GREEN** — the minimum code that passes
3. **REFACTOR** — with the test still green

## The framework is Minitest, not RSpec

`ActiveSupport::TestCase`, `test "…" do … end`, `assert_*` — no `describe`/`it`, no `let`, no `expect().to`, no RSpec doubles. Stubbing is `Minitest::Mock` and `Object#stub` (`require "minitest/mock"`), which is how upstream tests are written and how every fork test must read.

```ruby
require "test_helper"
require "importmap/packager"

class Importmap::PackagerTest < ActiveSupport::TestCase
  setup { @packager = Importmap::Packager.new(Rails.root.join("config/importmap.rb")) }

  test "download retries a reset connection before giving up" do
    attempts = 0
    response = Class.new do
      def code() "200" end
      def body() "export default 1" end
    end.new
    flaky = ->(_uri) { attempts += 1; raise Errno::ECONNRESET, "SSL_connect" if attempts < 3; response }

    without_retry_wait do
      Dir.mktmpdir do |vendor_dir|
        packager = Importmap::Packager.new(Rails.root.join("config/importmap.rb"), vendor_path: Pathname.new(vendor_dir))

        Net::HTTP.stub(:get_response, flaky) { packager.download("react", "https://ga.jspm.io/npm:react@17.0.2/index.js") }
      end
    end

    assert_equal 3, attempts
  end
end
```

Three things that example is doing on purpose. A stubbed response is a tiny object with `code` and `body` — no `Net::HTTPResponse` construction. Anything that **writes** takes a `vendor_path` inside `Dir.mktmpdir`. The default is a relative `vendor/javascript` resolved against the working directory, not against `Rails.root`, and the suite never chdirs — so a download without it leaves `vendor/javascript/react.js` at the **repo root**. And `without_retry_wait` (in `packager_test.rb`) zeroes `HttpRetries.wait` and restores it in `ensure` — any test that sets a class-level accessor (`Packager.endpoint`, `Npm.base_uri`, `HttpRetries.attempts`) restores it the same way or it leaks into later tests.

## Where each kind of test lives

| Under test | File | Talks to |
|---|---|---|
| `Importmap::Map` (DSL, `to_json`, preloads, integrity, cache) | `test/importmap_test.rb` | nothing — draws a map in `setup` against `test/dummy` |
| View helpers | `test/importmap_tags_helper_test.rb` | nothing |
| `Reloader` | `test/reloader_test.rb` | nothing |
| `Packager` logic (pin lines, provenance, esm.run rewriting, retries) | `test/packager_test.rb`, `test/packager_single_quotes_test.rb` | nothing — `Net::HTTP.stub` / `@packager.stub(:post_json, …)` |
| `Npm` logic (outdated, audit parsing) | `test/npm_test.rb` | nothing — `npm.stub(:get_json, …)` |
| `Minifier` (tool discovery, argv, errors) | `test/minifier_test.rb` | the filesystem; real tool only when one is installed |
| `bin/importmap` end to end | `test/commands_test.rb` | **live** jspm, jsDelivr, npm registry |
| Live-contract checks | `test/packager_integration_test.rb`, `test/npm_integration_test.rb` | **live** |
| `rails importmap:install` | `test/installer_test.rb` | generates a Rails app into a tmpdir |

The default is a unit test with the network stubbed. Add a `commands_test.rb` case only when the behaviour is about the CLI's contract with a real CDN response (a new `--from` provider, a new output line) — every one of those tests costs a network round-trip on every CI cell.

## How the command tests work (read before adding one)

`CommandsTest` includes `ActiveSupport::Testing::Isolation`: **each test runs in a forked process**, copies `test/dummy` to a fresh tmpdir, `chdir`s into it and runs the real `bin/importmap` with `system`. Consequences:

- Set up state with the helpers: `importmap_config('pin "md5", …')` writes `config/importmap.rb`; `run_importmap_command("pin", "md5@2.2.0")` runs the CLI and **flunks with the CLI's own output** if it exits non-zero, so the reason a live CDN said no is in the failure message.
- Assert on the CLI's printed sentences and on the resulting files (`config/importmap.rb`, `vendor/javascript/*.js`) — that is the contract users see.
- Pin exact versions in the test (`md5@2.2.0`) so a CDN publishing a new release cannot change the expected output.
- `--minify` tests must `skip … unless minifier_available?`. The skip message names the tools; CI installs bun so the skip never fires there.
- Nothing leaks between tests, but nothing is shared either: no memoised state, no class-level setup.

## Fixtures

`test/fixtures/files/*_import_map.rb` are real `config/importmap.rb` files exercising one shape each: outdated (double- and single-quoted, with and without a CDN), without CDN and versions, invalid, scoped package (plain and with a nested path), nested package path (plain and with a comment), locked, remote with a reason, vulnerable. Add a fixture for a new pin-line shape rather than building strings in the test; name it for the shape. For a pin line that only one test needs, `create_temp_importmap` (a private helper in `packager_test.rb`) writes a Tempfile and returns its path; `file_fixture("…_import_map.rb")` is for shapes reused across tests and raises if the file does not exist.

## The CI matrix is part of the test

`ci.yml` runs Ruby 3.1–4.0 × Rails 6.1–main × sprockets/propshaft. Things that pass locally and fail in a cell:

- `ENV["ASSETS_PIPELINE"]` — `importmap_test.rb` branches on it for integrity/digest expectations; a new asset-path assertion needs both branches
- Rails 6.1 needs `logger`, `mutex_m`, `drb`, `bigdecimal` added explicitly (see `Appraisals`) — a new stdlib use may need the same
- Ruby 3.1 has no `Data.define` and no anonymous `*`/`**` argument forwarding; the gemspec floor is 3.1 and the code has to honour it
- `gemfiles/*.lock` are deleted before install, so a cell resolves fresh every run

Run the nearest cell locally before pushing a change to the engine, the Map or the helpers:

```bash
BUNDLE_GEMFILE=gemfiles/rails_7.1_sprockets.gemfile bundle install
BUNDLE_GEMFILE=gemfiles/rails_7.1_sprockets.gemfile ASSETS_PIPELINE=sprockets bundle exec rake test
```

## A CDN failure is not a flake until proven

The live tests fail when jspm rate-limits a burst or jsDelivr resets a connection. `HttpRetries` (3 attempts, growing pause) is the harness-level answer and it is already in place. The correct reaction to a red live test is `/lode:debug-flaky`, never a `retry`, `sleep` or `skip` around the assertion. Two full matrices hitting the same endpoints at once is what the `on: push: branches: [main]` guard in `ci.yml` prevents — don't widen it.

## Coverage

- **80% minimum** overall
- **100%** for `Packager` pin-line rewriting and provenance, `Minifier`, `HttpRetries`, and `Map#to_json` / `preloaded_module_paths` — a wrong import map breaks every page of every app

## Checklist

- [ ] Test written and seen failing BEFORE the implementation
- [ ] Unit tests stub the network; only `commands_test.rb` and `*_integration_test.rb` go live
- [ ] Exact package versions in any live test
- [ ] `--minify` paths skip cleanly without a tool and were actually run locally with one
- [ ] Both `ASSETS_PIPELINE` branches covered if an asset-path expectation changed
- [ ] `bundle exec rake test` green, plus the nearest matrix cell for engine/Map/helper changes
