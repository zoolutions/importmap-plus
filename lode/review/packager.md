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
