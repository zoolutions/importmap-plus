How the suites assert, where a loose assertion has already let a regression through.

### Docs page request specs parse the response with Nokogiri and assert the masthead `h1` includes the document title
- **Holds because:** the docs shell renders the sidebar, which lists every page title, so `expect(response.body).to include(doc.title)` passes for a page whose own content failed to render — the title it matched came from the sidebar link to some other page. Parsing and reading `at_css("h1")` pins the masthead heading of the page under test, and parsing also means a title containing an escaped `&` still matches.
- **Where:** `docs/spec/requests/docs_spec.rb` (the `Doc.all.select(&:view_class).each` render loop)
- **Proven by:** `docs/spec/requests/docs_spec.rb:"renders the <slug> page"` (one example per registered page)
- **Origin:** cubic learning 5faccca0

### A test for a provider split asserts the end state of both pins, not just the one that moved
- **Holds because:** the bug being locked in is one spec taking another down with it — grouping a subpath with its package sends both to one CDN, and a single unresolvable spec fails the whole batch. Asserting only the subpath's new URL passes just as well when the package silently stopped updating too, which is the other half of the regression. The provider-split cases assert the subpath moved *and* that the package's own pin is still exactly where it was, with the CLI's message naming one spec rather than two.
- **Where:** `test/commands_test.rb:"update command resolves a subpath pin from its own CDN, not its package's"` (and the sibling `update command with a subpath name re-pins only that key`)
- **Proven by:** `test/commands_test.rb:"update command resolves a subpath pin from its own CDN, not its package's"`
- **Origin:** PR #23

### A pin line only one test needs goes through `create_temp_importmap`; a shape reused across tests is a fixture file
- **Holds because:** `test/fixtures/files/` holds twelve `*_import_map.rb` fixtures, each one shape, and `file_fixture` raises when the file does not exist. Building a one-line map for a single assertion as a thirteenth fixture file, or inlining a reused shape as a string, are the two mistakes the retired local `/tdd` guarded against; the guidance now lives in `.claude/rules/testing.md` → Fixtures, which the plugin's `/lode:tdd` reads for the fixture convention.
- **Where:** `test/packager_test.rb#create_temp_importmap` (private; writes a Tempfile and returns its path); `.claude/rules/testing.md` → Fixtures
- **Proven by:** `test/packager_test.rb:"extract_existing_pin_options with preload false"` and its three neighbours use the helper; the remote-reason tests use `file_fixture("remote_reason_import_map.rb")`
- **Origin:** gate 2026-09-15 (PR #30)
