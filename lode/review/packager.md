How `Importmap::Packager` resolves, downloads and rewrites pins — the invariants a change to `packager.rb` must keep.

### `locked_pin_line` derives a version from `to:` only when the value is a remote URL
- **Holds because:** a vendored pin such as `pin "md5", to: "md5.js"` has no version anywhere on the line; reading `to:` unconditionally would look for `@x.y.z` in a filename and hand back a lock built on nothing. When `to:` fails `REMOTE_URL_REGEXP` (or carries no version) the method returns nil and `lock` prints `Can't lock "<pkg>": its pin has no version` instead of writing a bogus `# @… (locked)`.
- **Where:** `lib/importmap/packager.rb#locked_pin_line` (with `REMOTE_URL_REGEXP`, `extract_package_version_from`), consumed by `lib/importmap/commands.rb#lock_package`
- **Safe direction:** returning nil is the harmless failure — the user is told the pin has no version and can pass an explicit version to `pin --lock`; a fabricated lock silently freezes a package at a version nobody chose.
- **Proven by:** `test/packager_test.rb:"locked_pin_line returns nil when there is no version to lock at"`
- **Origin:** cubic learning 89c2d696

### An esm.run bundle that imports one package at two versions is warned about, and the first version requested is the one pinned
- **Holds because:** an import map maps a bare specifier to exactly one file, so a bundle importing `dep@1.0.0` and `dep@2.0.0` can only get one of them. `rewrite_esm_run_imports` collects every version seen per key, keeps the first in `dependencies`, and `warn`s naming the key and all the versions rather than picking silently and leaving the app to discover the wrong copy at runtime.
- **Where:** `lib/importmap/packager.rb#rewrite_esm_run_imports` (the `versions` hash and its `warn`)
- **Proven by:** `test/packager_test.rb:"download warns when a bundle imports one dependency at two versions"`
- **Origin:** cubic learning 08aeec11

### `ESM_RUN_IMPORT_REGEXP` rewrites a `/npm/…/+esm` URL only where an `import`/`from` keyword precedes it
- **Holds because:** the pattern requires `from` or `import` (including the `import(` dynamic form) before the quote, so a data string such as `const path = "/npm/foo@1.0.0/+esm"` inside the bundle keeps its literal text. Rewriting it would turn a runtime string the bundle uses as data into a bare specifier the import map then fails to resolve. The keyword is the whole of the protection: `rewrite_esm_run_imports` is a `source.gsub` with no notion of being inside a literal, so a *string whose contents* spell `from "/npm/foo@1/+esm"` is still rewritten. No published esm.run bundle has been seen to contain one, and the gem takes no JavaScript parser as a dependency, so the keyword anchor is the accepted limit rather than a guarantee.
- **Where:** `lib/importmap/packager.rb#ESM_RUN_IMPORT_REGEXP`, applied in `#rewrite_esm_run_imports`
- **Safe direction:** leaving a specifier unrewritten is the harmless miss — the absolute `/npm/…/+esm` URL still loads from jsDelivr; rewriting a data string corrupts the file with no error.
- **Proven by:** `test/packager_test.rb:"download only rewrites an esm.run bundle's module specifiers"`
- **Origin:** cubic learning 6c60d3f7

### A vendored file is written to a pid-suffixed partial and renamed over the target, so a failed download never destroys the file the app has
- **Holds because:** `save_vendored_package` writes `<target>.<pid>.download`, then `File.rename`s it over the target — atomic on the same filesystem. A write that dies partway (ENOSPC, a killed process) leaves the working file untouched and the partial is removed in the `rescue`. `remove_existing_package_file` runs only when a *directory* occupies the target, which is the one case rename cannot replace. The pid suffix keeps two shells pinning the same package from writing or cleaning up each other's partial.
- **Where:** `lib/importmap/packager.rb#save_vendored_package` (and `#download_package_file`, which validates before it is called)
- **Proven by:** `test/packager_test.rb:"download leaves the file an app has when the replacement can't be written"`
- **Origin:** cubic learning 82466694; PR #22

### A CDN spec built for a subpath key puts the version on the package name: `name@version/subpath`
- **Holds because:** `photoswipe/lightbox` at `@5.4.4` is `photoswipe@5.4.4/lightbox` on every CDN; `photoswipe/lightbox@5.4.4` is a path none of them has, and jspm answers 404 for the *whole batch* when one spec is unresolvable, so a single malformed spec leaves every package in that group unpinned. `package_spec_for` splits the key with `PACKAGE_SPEC_REGEXP` and inserts the version between name and subpath.
- **Where:** `lib/importmap/packager.rb#package_spec_for` (with `PACKAGE_SPEC_REGEXP`, `package_key_for`, `package_name_for`)
- **Proven by:** `test/packager_test.rb:"package_spec_for puts the version ahead of the subpath"`; `test/commands_test.rb:"update command re-resolves a remote subpath pin from the CDN it is on"`
- **Origin:** cubic learning 360fdf78; PR #13

### The import map is re-read after every pin is written, so a same-command dependency lookup sees the pin just added
- **Holds because:** `Packager#importmap` memoises the file's contents. Pinning an esm.run bundle appends the bundle's pin and then recurses into its dependencies asking `packaged?` about each; against a stale cache a dependency already pinned this run reads as unpinned and is pinned a second time. `update_importmap_with_pin` calls `packager.reload!` after every write.
- **Where:** `lib/importmap/packager.rb#reload!`; `lib/importmap/commands.rb#update_importmap_with_pin`, `#pin_esm_run_dependencies`
- **Proven by:** `test/packager_test.rb:"reload! drops the cached import map so a pin written now is seen next"`; `test/commands_test.rb:"pin command with --from esm.run pins a shared dependency once"`
- **Origin:** cubic learning 1f57a939

### A rewritten graph file is inspected again, so a specifier the crawl counted but the rewrite couldn't touch keeps the whole package remote
- **Holds because:** the crawl reads `ModuleInspector#code` (block comments discounted) while the rewrite runs `IMPORT_REGEXP` over the raw source, and the two disagree about at least one real form: `import(/* webpackChunkName: "leaf" */ "./leaf.js")` is discovered and fetched, and `\s*` can't cross the comment, so the file is written still asking the browser for `./leaf.js` beside a digested asset path. The entry is caught by `ensure_servable`; a *sibling* is not, because nothing inspects it after the rewrite. `#verify_rewritten` inspects every rewritten source — siblings and entry — and raises `Unownable` if any still carries a relative import, which also catches the unterminated-literal and quote-in-path forms without naming them.
- **Where:** `lib/importmap/package_graph.rb#verify_rewritten`, called from `#crawl`
- **Safe direction:** refusing is harmless — the package stays on its CDN and works; shipping an unrewritten specifier is a 404 on the page.
- **Proven by:** `test/package_graph_test.rb:"keeps the whole package remote when a specifier it crawled comes back unrewritten"`
- **Origin:** gate round 1 (parser), PR #30

### `PackageGraph::PATH_REGEXP` matches a path segment at a time, because the path becomes a write
- **Holds because:** the paths come from a CDN and are joined onto a directory. A single character class over the whole path accepted `dist//a.js`, whose key (`pkg/dist//a`) is not the key `Importmap::Map` gives the file it writes, and `..//tmp/evil.js`, which `URI.join` leaves as `/tmp/evil.js` under the package root — `Pathname#join` then returns an absolute path and the write lands outside `vendor/javascript` entirely, where the partial's own cleanup can't reach it. Each segment must now be a plain name that doesn't start with a dot, which refuses `..`, an empty segment, a leading `/` and a dot-directory (which `Map`'s `**/*.js{,m}` glob never descends into) in one rule. `VendoredGraph#write` asserts the joined path is still inside the partial.
- **Where:** `lib/importmap/package_graph.rb#PATH_REGEXP`, `#vendorable_path?`; `lib/importmap/vendored_graph.rb#write`
- **Safe direction:** refusing keeps a working remote pin; a write outside the vendor directory is the one failure with no undo.
- **Proven by:** `test/package_graph_test.rb:"keeps the whole package remote when a relative path leaves the package root sideways"`, `:"…when a sibling hides in a dot directory"`
- **Origin:** gate round 1 (parser), PR #30

### A graph directory is this gem's to replace or delete only when the import map maps it *with the comment this gem writes*
- **Holds because:** `pin lodash --vendor` downloads the entry alone and clears the directory a previous graph left — and an app that keeps its own `vendor/javascript/lodash` would have lost it, because the removal ran before anything checked whose directory it was. Ownership is now `VendoredGraph#mapped?`, which requires the line to name the directory **and** carry `# @<version> (graph of <package>)`; a `pin_all_from` an app wrote itself has no such comment, so it is never rewritten and its directory never deleted.
- **Where:** `lib/importmap/vendored_graph.rb#line_regexp_for`, `#mapped?`, `#commit`, `#remove`
- **Safe direction:** leaving a stale directory is untidy; deleting an app's own source is unrecoverable.
- **Proven by:** `test/packager_test.rb:"download without a graph leaves a directory the import map doesn't map"`, `:"download without a graph vendors the entry alone and drops the directory its pin maps"`; `test/vendored_graph_test.rb:"a line is found by its own directory and by no other"`
- **Origin:** gate round 1 (parser), PR #30

### An entry and its graph directory are written as one unit, and the directory is swapped by rename, not by delete-then-rename
- **Holds because:** the entry's rewritten specifiers name the chunks in its directory, so a new entry beside an old directory is as broken as an old entry beside a new one: both partials are built before either is committed, and only the two renames are exposed to a crash. The directory swap renames the old one aside, moves the new one in and removes the old, restoring it if the move fails — `rm_rf` then `rename` left a window the width of a recursive delete in which the app had no directory at all while `pin_all_from` still mapped it.
- **Where:** `lib/importmap/packager.rb#save_vendored_package`, `#write_entry_partial`, `#commit_entry`; `lib/importmap/vendored_graph.rb#write`, `#commit`
- **Proven by:** `test/vendored_graph_test.rb:"commit puts the directory the app has back when the swap fails"`; `test/packager_test.rb:"download leaves the graph an app has when the crawl refuses"`, `:"download leaves the file an app has when the replacement can't be written"`
- **Origin:** gate round 1 (correctness, rules), PR #30

### `fetch_remote` lets Net::HTTP negotiate the encoding and asks for identity only when the body comes back unreadable
- **Holds because:** jspm answers some files `content-encoding: br` however the request advertises itself (`@popperjs/core@2.11.8/lib/utils/computeAutoPlacement.js` is one), and Net::HTTP decodes gzip and deflate only, so those bytes reach `ModuleInspector` as invalid UTF-8 and raise `ArgumentError`. Sending `Accept-Encoding: identity` up front fixes that and breaks more: `Net::HTTPGenericRequest` sets `decode_content` **only** when the caller supplies no accept-encoding, so every gzip answer would then arrive compressed and be written to `vendor/javascript` as bytes on the `force: true` paths. The request is therefore made normally, and repeated with `IDENTITY_ENCODING` only when the body is not valid UTF-8.
- **Where:** `lib/importmap/packager.rb#fetch_remote`, `#encoded?`, `IDENTITY_ENCODING`
- **Proven by:** `test/packager_test.rb:"fetch_remote asks again for an unencoded body when the CDN encoded one Net::HTTP can't read"`, `:"fetch_remote lets Net::HTTP negotiate an encoding it can read"`
- **Origin:** gate round 1 (correctness), PR #30

### `remove_package_from_importmap` re-reads the file it just rewrote
- **Holds because:** `#importmap` memoises, and `remove` is followed by a caller asking whether the pin is still there — `unpin` does it for the next package, and `Packager#remove` itself now reads the map (through `VendoredGraph#mapped?`) *before* removing the pin, which primed the memo. Without the `reload!`, `packaged?` answered from the file as it was and reported a pin that had just been deleted.
- **Where:** `lib/importmap/packager.rb#remove_package_from_importmap`
- **Proven by:** `test/packager_test.rb:"remove takes the graph directory and its line with the pin"` (asserts `packaged?` on the same instance afterwards); `test/packager_single_quotes_test.rb:"remove package with single quotes"`
- **Origin:** PR #30

### A graph directory is replaced only when the import map maps it as ours, never merely because it is in the way
- **Holds because:** the directory is named for the pin, so it can collide with one an app vendored by hand and mapped with its own `pin_all_from` (no `(graph of …)` comment). `#commit` renames the old directory aside and removes it, which for such a directory is unrecoverable loss of files this gem never wrote. Round 1 guarded the *delete* path and left the *replace* path open; both now go through `mapped?`, and a directory that exists without being mapped as ours raises `VendoredGraph::Occupied`. `pin` prints `Skipping "<pkg>": <dir> already exists and isn't a graph directory this gem wrote` and writes nothing at all — not even the pin — so the app can move its directory and try again.
- **Where:** `lib/importmap/vendored_graph.rb#commit`, `Occupied`; `lib/importmap/commands.rb#pin_vendored_package`, `#restore_package`
- **Safe direction:** doing nothing and saying so is recoverable; renaming an app's directory away is not.
- **Proven by:** `test/vendored_graph_test.rb:"commit refuses to replace a directory the import map doesn't map as ours"`; `test/packager_test.rb:"download refuses to replace a directory the import map doesn't map as ours"`
- **Origin:** gate round 2 (correctness), PR #30

### `force` skips the single-file check only when the download is the shape the pin says it is
- **Holds because:** `pristine` passes `force: true` with `graph: true` for a pin that maps a graph. If the CDN it restores from can't be crawled — `--from skypack`, `--from esm.sh`, a custom URL — the crawl returns nil, and skipping the check as well would write the entry with its relative imports intact and then delete the directory those imports resolve through: a broken page, from the repair command, silently. The check therefore runs whenever a graph was asked for and none came back, so `pristine` reports the package and skips it. `--vendor` (`graph: false`) still skips the check entirely, which is what the flag means.
- **Where:** `lib/importmap/packager.rb#download_package_file` (`unless force && (@last_graph || !graph)`)
- **Proven by:** `test/packager_test.rb:"download checks a forced entry whose pin maps a graph the CDN didn't give"`, `:"download vendors a source that isn't an ES module when forced"`; `test/commands_test.rb:"pristine command with --from esm.run drops the graph a jspm pin had"` (the bundling case that must still pass)
- **Origin:** gate round 2 (correctness), PR #30

### A partial is removed by the method that created it, because a failure halfway leaves the caller without its name
- **Holds because:** `save_vendored_package`'s rescue can only clean up partials whose paths it has been handed back, and a minifier raising on the twentieth of forty-seven files, or a full disk during the entry write, raises before the return. Each writer therefore cleans up its own: `VendoredGraph#write` rescues around the whole directory, `Packager#write_entry_partial` around the file. Otherwise a `<dir>.<pid>.download` directory of half-written chunks stays in `vendor/javascript` for the asset pipeline to serve, and no later run removes it — the pid in the name is a different pid by then.
- **Where:** `lib/importmap/vendored_graph.rb#write`; `lib/importmap/packager.rb#write_entry_partial`, `#save_vendored_package`
- **Proven by:** `test/vendored_graph_test.rb:"write cleans up its own partial when a file can't be written"`; `test/packager_test.rb:"download leaves the file an app has when the replacement can't be written"`
- **Origin:** gate round 2 (correctness), PR #30

### A body that is still unreadable after the identity retry is an error with a sentence, not bytes handed on
- **Holds because:** `fetch_remote` returning an undecodable body only moves the failure to `ModuleInspector`, which raises `ArgumentError: invalid byte sequence in UTF-8` with no mention of the file — and on a 48-file crawl, once per file. After the retry the method raises `HTTPError, "Can't read <url>: the CDN sent an encoding this gem can't decode"`, which `pin` reports and `pristine` counts as a package it couldn't restore.
- **Where:** `lib/importmap/packager.rb#fetch_remote`, `#encoded?`
- **Origin:** gate round 2 (parser), PR #30
