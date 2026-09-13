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

### A live CLI test whose setup is the command under test asserts the setup worked, or it passes on the base
- **Holds because:** `test "unpin command removes a vendored graph with its pin"` set up with `run_importmap_command("pin", "@popperjs/core@2.11.8")` and then asserted the directory was gone. On `main` that `pin` keeps the package remote and writes no directory, so every assertion held and the test passed without the feature — as did the `--remote` and `--vendor` graph tests. Each now asserts the graph directory exists between the setup and the command under test, which is what makes them fail on the base.
- **Where:** `test/commands_test.rb:"unpin command removes a vendored graph with its pin"`, `:"pin command with --remote keeps a chunked package on its CDN and takes the graph it had"`, `:"pin command with --vendor drops the graph a package had"`
- **Origin:** gate round 1 (tests), PR #30

### `[nil].one?` is false: a stub that counts its calls counts them with `size`
- **Holds because:** `Enumerable#one?` without a block counts *truthy* elements, so a lambda recording headers as `sent << headers; sent.one? ? first : second` hands back the second response on the first call when the first call's headers are nil — and the test then asserts against a request sequence that never happened. Count with `sent.size == 1`.
- **Where:** `test/packager_test.rb:"fetch_remote asks again for an unencoded body when the CDN encoded one Net::HTTP can't read"`
- **Origin:** PR #30
