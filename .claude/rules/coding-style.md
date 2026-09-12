# Coding Style Rules

## Two kinds of file

This is a fork, so style is a merge-cost decision before it is a taste decision.

| File | Owner | Style rule |
|---|---|---|
| `map.rb`, `engine.rb`, `reloader.rb`, `npm.rb`, `commands.rb`, `packager.rb`, helpers, `lib/install/`, `test/importmap_test.rb`, `test/npm_test.rb` … | upstream (modified here) | **Match upstream exactly.** No reformatting, no reordering, no renaming for taste. Add; don't rearrange. |
| `minifier.rb`, `http_retries.rb`, `test/minifier_test.rb`, `bin/release`, `CHANGELOG.md`, `.github/workflows/release.yml`, `docs/` | this fork | Same conventions, but you own the shape. |

When a change to an upstream-owned file grows past a few dozen lines, ask whether it belongs in a new file that the upstream file calls into — that is how `Minifier` and `HttpRetries` were added and why they never conflict.

## Upstream's Ruby conventions (follow them everywhere)

```ruby
# Space-padded array literals
RETRYABLE_ERRORS = [ SocketError, SystemCallError, Timeout::Error ].freeze

# Internals marked, not hidden: constants public with :nodoc:
PIN_REGEX = /^pin\s+["']([^"']+)["']/.freeze # :nodoc:

# private, then indented methods
class Importmap::Packager
  def import(*packages, env: "production", from: "jspm")
    # …
  end

  private
    def post_json(body)
      # …
    end
end

# Thor commands print with puts %(…) and speak to the user in full sentences
puts %(Pinning "#{package}" to #{packager.vendor_path}/#{package}.js via download from #{url})

# Errors are small classes on the owning class
Error        = Class.new(StandardError)
HTTPError    = Class.new(Error)
```

Compact-form accessors and endless defs are fine where upstream already uses them (`def retry_attempts = Importmap::HttpRetries.attempts`).

## Comments

Comments explain **why**, never what. The fork's own files set the bar: a paragraph above a regex saying what it deliberately does not do (`ESM_RUN_IMPORT_REGEXP`), a note on why Windows needs `.cmd` shims, why a lockfile is pinned. A comment that restates the next line is noise; delete it.

No commented-out code. No `TODO` without an issue number.

## File organisation

- **Many small files over few large ones** — 200–400 lines typical, 800 max. `packager.rb` is the biggest file in the gem and at the limit; new Packager behaviour goes in a collaborator, not another 100 lines.
- One class per file, named for the class. Fork-only collaborators live next to the upstream file that uses them (`lib/importmap/minifier.rb` beside `packager.rb`).
- No new top-level namespaces: everything stays under `Importmap::`.

## Error handling

```ruby
# Good: a bounded retry, then the class's own error with the reason in it
def with_retries(description)
  # …
  raise self.class::HTTPError, "Unexpected transport error #{description} (#{error.class}: #{error.message})"
end

# Good: rescue the one thing you expect and add context
def provider_for_url(url)
  PROVIDER_HOSTS[URI(url.to_s).host]
rescue URI::InvalidURIError
  nil
end

# Bad: silence
rescue StandardError
  nil
end
```

- A CLI command that cannot do what was asked says so on stdout in a sentence and exits non-zero. `Commands.exit_on_failure?` is `false` deliberately (upstream); raise `Thor::Error` or `Packager::Error` and let Thor print it.
- Never `rescue` around a CDN call to "make the test pass" — the retry lives in `with_retries`, and after that the error is the correct outcome.

## Shell-outs and files

- Shell out with `Open3.capture3(executable, *argv)` — an argv array, never a string, never `system("… #{input}")`. Package names and paths reach these calls from the network.
- Build vendored paths through `vendored_package_path` / `package_filename`; nowhere else joins `vendor_path` with user input.
- Work in a `Dir.mktmpdir` and write the final file last, so a failed minify or download never leaves a half-written `vendor/javascript/*.js`.

## Code quality checklist

Before marking work complete:

- [ ] Upstream-owned files: the diff is additive and reads in upstream's style
- [ ] New behaviour of any size lives in its own file
- [ ] Methods are small (< 30 lines ideal, < 50 max); no nesting deeper than 4 levels
- [ ] Every outbound request goes through `with_retries`
- [ ] Every shell-out passes an argv array
- [ ] Comments say why; none restate the code
- [ ] `bundle exec rake test` passes with a minifier installed (so the `--minify` tests ran, not skipped)
