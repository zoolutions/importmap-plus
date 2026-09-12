---
description: "Use when implementing any feature or fixing any bug — enforces RED-GREEN-REFACTOR with Minitest: write the failing test first, implement the minimum, then refactor."
model: sonnet
---

# TDD Command

Enforce RED → GREEN → REFACTOR with Minitest (`ActiveSupport::TestCase`). Read `.claude/rules/testing.md` for where each kind of test lives and how the command tests work.

## The cycle

```text
RED:      write a failing test — it MUST fail first, for the right reason
GREEN:    the MINIMUM code that passes
REFACTOR: improve with the test still green
REPEAT
```

## When to use

- A new CLI option or provider
- A change to how a pin line is written or read back
- A bug (write the test that reproduces it FIRST — usually a fixture under `test/fixtures/files/` with the offending line)
- A Map / helper change (both `ASSETS_PIPELINE` branches)
- A registry (Npm) change

## Workflow

### Step 1: Write the failing test (RED)

Pick the file by what's under test — stubbed unit test by default:

```ruby
# test/packager_test.rb
test "update keeps preload: false when re-pinning a vendored package" do
  packager = Importmap::Packager.new(create_temp_importmap(<<~RUBY))
    pin "md5", preload: false # @2.1.0
  RUBY

  line = packager.vendored_pin_for("md5", "https://ga.jspm.io/npm:md5@2.2.0/md5.js", false)

  assert_equal 'pin "md5", preload: false # @2.2.0', line
end
```

`create_temp_importmap` (a private helper in `packager_test.rb`) writes a Tempfile and returns its path — reach for it when the pin line under test is one or two lines. `file_fixture("…_import_map.rb")` is for shapes reused across tests, and the file must already exist under `test/fixtures/files/`; it raises if not.

Only when the behaviour IS the CLI's contract with a real CDN response, a live case:

```ruby
# test/commands_test.rb — runs bin/importmap in a tmp copy of test/dummy, against live jspm/jsDelivr
test "pin --minify writes the minified banner and provenance" do
  skip "no JavaScript minifier installed (bun, esbuild or terser)" unless minifier_available?
  importmap_config("")

  out, _err = run_importmap_command("pin", "md5@2.2.0", "--minify")

  assert_includes out, 'Pinning "md5" to vendor/javascript/md5.js via download from https://ga.jspm.io/npm:md5@2.2.0/md5.js (minified)'
  assert_includes File.read("#{@tmpdir}/dummy/config/importmap.rb"), 'pin "md5" # @2.2.0 (minified)'
end
```

Exact versions in live tests. Assert on the printed sentence and on the file left behind.

### Step 2: Run it — verify FAIL

```bash
bundle exec ruby -Itest test/packager_test.rb -n /preload:\ false/
```

The failure must be the missing behaviour (`NoMethodError`, a wrong string), not a broken fixture or a typo. This confirms the test runs, tests the right thing, and the behaviour doesn't already exist.

### Step 3: Implement the minimum (GREEN)

The smallest change — in a fork-only collaborator if it is more than a few lines in an upstream-owned file.

### Step 4: Run it — verify PASS

```bash
bundle exec ruby -Itest test/packager_test.rb -n /preload:\ false/
```

### Step 5: Refactor

- Extract to a collaborator if `packager.rb` grew
- Names that say what the CDN or pin line means, not how the regex works
- Sibling wrongness in the same file (`.claude/rules/striving-for-excellence.md`)

### Step 6: The full suite

```bash
bundle exec rake test        # live CDN tests included; confirm --minify cases ran, not skipped
```

Engine/Map/helper change? Also the nearest matrix cell:

```bash
BUNDLE_GEMFILE=gemfiles/rails_7.1_sprockets.gemfile bundle install
BUNDLE_GEMFILE=gemfiles/rails_7.1_sprockets.gemfile ASSETS_PIPELINE=sprockets bundle exec rake test
```

## Coverage requirements

| Code | Minimum |
|---|---|
| All code | 80% |
| `Packager` pin-line rewriting and provenance | 100% |
| `Minifier`, `HttpRetries` | 100% |
| `Map#to_json`, `preloaded_module_paths` | 100% |

## Test shapes to include

**Unit (stubbed)** — happy path; scoped package; subpath; single-quoted pin; `preload: false` / array preload; remote pin; a package with no version comment; a malformed line (`Map::InvalidFile`); a 429 then a 200 (`HttpRetries`).

**Live (`commands_test.rb`)** — one case per new CDN contract, exact versions, asserting output sentence + resulting file.

**Fixture** — a new `test/fixtures/files/<shape>_import_map.rb` for any new pin-line shape.

## Best practices

**DO**
- See the test fail before writing code
- Stub `Net::HTTP` (`Net::HTTP.stub(:get_response, …)`) or the instance (`@packager.stub(:post_json, …)`) in unit tests
- Assert the exact CLI sentence — users read it, and the docs quote it
- Test both asset pipelines when the Map is involved

**DON'T**
- Add a live test for logic a stub can prove
- `retry`, `sleep` or `skip` around a live assertion that failed — that is `/debug-flaky`'s job
- Test regex internals; test the pin line in and the pin line out
- Reorder or rename upstream's existing tests

## Checklist

- [ ] Test written BEFORE the implementation and seen red
- [ ] Minimum code to green
- [ ] Refactored with tests green
- [ ] Coverage met for the touched area
- [ ] Edge cases from the list above covered
- [ ] `bundle exec rake test` green, `--minify` cases ran
