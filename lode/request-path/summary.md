# Request path

## What this does, and the governing invariant

The request path renders an app's import map into HTML: an `Importmap::Map` built once at boot from `config/importmap.rb` is turned into JSON, `<script type="importmap">`/`<link rel="modulepreload">` tags, and an ETag, on every page render. The invariant this path is built around (`CLAUDE.md`, "Architecture"): engine → `Map` → helpers never reach a CDN or registry — only the CLI (`Commands` → `Packager`/`Npm`) does. Concretely, `Importmap::Map` (`lib/importmap/map.rb`) does no HTTP; the only I/O it performs on a request is calling into the asset resolver (`resolver.path_to_asset`, `resolver.asset_integrity`) that Sprockets or Propshaft already provides — `map.rb:222-224`, `map.rb:256-264`. In production (`config.cache_classes` true) that is also the *only* filesystem I/O on the path, because the reloader and cache-sweeper initializers that add per-request `File.mtime` checks are gated off in that mode (`engine.rb:22-23`, `engine.rb:33`). In development/test those two mechanisms add a per-request stat-based check so pin changes are picked up without a restart — see "Engine wiring" below; that is a deliberate dev/test convenience, not a violation of the production contract.

## The DSL — public API of `Importmap::Map`

- **`draw(path = nil, &block)`** — `map.rb:20-33`. Reads and `instance_eval`s a `config/importmap.rb`-shaped file (or a block) into the receiver. Wraps any `StandardError` from the eval in `Importmap::Map::InvalidFile`, logging first. Called once at boot per configured path (`engine.rb:19`) and again by the reloader when a watched file changes (`reloader.rb:8`).
- **`enable_integrity!`** — `map.rb:67-70`. Sets `@integrity = true` and clears the cache. Off by default; without it, no `integrity:` value (even an explicit string or `true`) is ever emitted — `resolve_integrity_value` short-circuits on `@integrity` (`map.rb:256-257`).
- **`pin(name, to: nil, preload: true, integrity: true)`** — `map.rb:72-75`. Registers one `MappedFile` (`name`, `path` defaulting to `"#{name}.js"`, `preload`, `integrity`) and clears the cache.
- **`pin_all_from(dir, under: nil, to: nil, preload: true, integrity: true)`** — `map.rb:77-80`. Registers a `MappedDir` describing a directory to expand at resolution time (not at `pin_all_from` time); clears the cache.
- **`preloaded_module_packages(resolver:, entry_point: "application", cache_key: :preloaded_module_packages)`** — `map.rb:137-155`. Expands packages+directories, filters to those preloaded for `entry_point` (`expanded_preloading_packages_and_directories`, `map.rb:267-269`: a boolean `preload` is preloaded for every entry point, a string/array `preload` only when it intersects `entry_point`), resolves each path through `resolver.path_to_asset`, drops unresolvable ones, and returns `{resolved_path => MappedFile}` with integrity resolved. Cached under `cache_key`.
- **`preloaded_module_paths(resolver:, entry_point: "application", cache_key: :preloaded_module_paths)`** — `map.rb:87-89`. Thin wrapper: `.keys` of `preloaded_module_packages`.
- **`to_json(resolver:, cache_key: :json)`** — `map.rb:162-168`. Expands all packages+directories (regardless of `preload`), resolves every path, builds `{"imports" => {...}, "integrity" => {...}}` (integrity key omitted when empty, `build_import_map`, `map.rb:235-240`), and `JSON.pretty_generate`s it. Cached under `cache_key`.
- **`digest(resolver:)`** — `map.rb:178-180`. `Digest::SHA1.hexdigest` of `to_json(resolver:).to_s` — used as an ETag component so an HTML cache invalidates when the map's resolved JSON changes.
- **`cache_sweeper(watches: nil)`** — `map.rb:185-194`. With `watches:`, builds (and memoizes on `@cache_sweeper`) an `ActiveSupport::EventedFileUpdateChecker` over the given directories (JS files only) that calls `clear_cache` on change; without `watches:`, returns the memoized checker. Built once by `engine.rb:36`, driven by a controller `before_action` (`engine.rb:39`).
- Cache mechanics are private: `cache_as(name) { ... }` (`map.rb:200-206`) memoizes per string key in `@cache`; `clear_cache` (`map.rb:208-210`) empties it and is called by every mutation (`draw`, `enable_integrity!`, `pin`, `pin_all_from`) so a redraw can never serve stale JSON.

## Engine wiring (`lib/importmap/engine.rb`)

- `config.importmap` is an `ActiveSupport::OrderedOptions` with `paths` (`[]`), `sweep_cache` (`Rails.env.development? || Rails.env.test?`), `cache_sweepers` (`[]`), `rescuable_asset_errors` (`[]`) — `engine.rb:8-12`.
- `config.autoload_once_paths` adds this engine's `app/helpers` and `app/controllers` — `engine.rb:14`.
- **`"importmap"`** (`engine.rb:16-20`) — runs at boot: creates `app.importmap = Importmap::Map.new`, appends `app.root.join("config/importmap.rb")` to `config.importmap.paths`, and `draw`s every path in that list. This is the only place `config/importmap.rb` is parsed on a normal boot.
- **`"importmap.reloader"`** (`engine.rb:22-30`) — unless `cache_classes`, builds an `Importmap::Reloader`, runs it once immediately (`reloader.execute`), registers it in `app.reloaders`, and hooks `app.reloader.to_run { reloader.execute }` so every framework reload cycle re-checks the watched paths.
- **`"importmap.cache_sweeper"`** (`engine.rb:32-42`) — only when `sweep_cache && !cache_classes`: appends `app/javascript` and `vendor/javascript` to `config.importmap.cache_sweepers`, builds the map's `cache_sweeper(watches:)`, and registers a `before_action` on `ActionController::Base` that calls `Rails.application.importmap.cache_sweeper.execute_if_updated` — an mtime check on every request in dev/test only.
- **`"importmap.assets"`** (`engine.rb:44-49`) — if `config.assets` exists (Sprockets or Propshaft present), adds `app/javascript` and `vendor/javascript` to `config.assets.paths`.
- **`"importmap.concerns"`** (`engine.rb:51-55`) — extends `ActionController::Base` with `Importmap::Freshness`, exposing `stale_when_importmap_changes`.
- **`"importmap.helpers"`** (`engine.rb:57-61`) — includes `Importmap::ImportmapTagsHelper` as a view helper.
- **`"importmap.rescuable_asset_errors"`** (`engine.rb:63-71`) — conditionally registers `Propshaft::MissingAssetError` and/or `Sprockets::Rails::Helper::AssetNotFound` into `config.importmap.rescuable_asset_errors`, based on which pipeline is `defined?`. `Map#rescuable_asset_error?` (`map.rb:212-214`) checks membership; `resolve_asset_path` (`map.rb:222-233`) rescues exactly those classes as "missing asset, skip it" and re-raises anything else.

## Reloader (`lib/importmap/reloader.rb`)

`Importmap::Reloader` delegates `execute_if_updated`, `execute`, `updated?` to a memoized `updater` (`reloader.rb:5,12-14`), an `ActiveSupport::FileUpdateChecker`-family watcher over `config.importmap.paths` whose change block is `reload!`. `reload!` (`reloader.rb:7-9`) re-`draw`s every configured path onto `Rails.application.importmap` — the *same* Map instance, so a redraw appends/overwrites pins rather than replacing the object (consistent with `pin`/`pin_all_from` overwriting by key in `@packages`/`@directories`, `map.rb:74`, `map.rb:79`). Only wired up when `!cache_classes` (`engine.rb:23`).

## Helpers and freshness

`Importmap::ImportmapTagsHelper` (`app/helpers/importmap/importmap_tags_helper.rb`):
- `javascript_importmap_tags(entry_point = "application", importmap: Rails.application.importmap)` (`:3-9`) — joins three tags with `\n`: the inline importmap `<script>`, the preload `<link>` tags for that entry point, and a `<script type="module">import "<entry_point>"</script>`.
- `javascript_inline_importmap_tag(importmap_json = ...to_json(resolver: self))` (`:13-16`) — one `<script type="importmap" data-turbo-track="reload">`, carrying the CSP nonce off `request&.content_security_policy_nonce` when present.
- `javascript_import_module_tag(*module_names)` (`:19-22`) — one `<script type="module">` containing one `import "<name>"` per argument.
- `javascript_importmap_module_preload_tags(importmap = ..., entry_point: "application")` (`:27-31`) — resolves `preloaded_module_packages` for that importmap/entry_point (cached under the entry point name) and emits one `<link rel="modulepreload">` per resolved path, `integrity:` set from the package.
- `javascript_module_preload_tag(*paths)` (`:34-36`) — same tag shape for arbitrary already-resolved paths, no integrity.
- All four preload/module tags funnel through the private `_generate_preload_tags` (`:39-46`), which also attaches the CSP nonce.

`Importmap::Freshness` (`app/controllers/importmap/freshness.rb:1-5`) exposes `stale_when_importmap_changes`, a class-level `etag { ... }` declaration (extended onto `ActionController::Base` by `engine.rb:53`) that adds `Rails.application.importmap.digest(resolver: helpers)` to the response's ETag computation, but only `if request.format&.html?`. This is how an import-map change (a new pin, a changed asset digest) busts an HTML page's browser/CDN cache without touching non-HTML responses.

## Both asset pipelines

The request-path code itself branches on pipeline presence only once, at boot: `engine.rb:64-70` registers `Propshaft::MissingAssetError` and/or `Sprockets::Rails::Helper::AssetNotFound` as rescuable, whichever is `defined?`. Nothing else in `map.rb`, the helpers, or the reloader inspects which pipeline is active — both resolvers are used purely through the duck-typed `path_to_asset` / `asset_integrity` interface.

The divergence shows up in test expectations, gated by `ENV["ASSETS_PIPELINE"]` (set by `.github/workflows/ci.yml:56` from the CI matrix's `assets-pipeline`, `ci.yml:28-51`; not read by any lib code):
- `test/importmap_test.rb:160-164` — `enable_integrity!` + `integrity: true` on `application`: under sprockets the expected hash is `sha256-47DEQpj8HBSa+/TImW+5JCeuQeRkm5NMpJWZG3hSuFU=` (a raw content digest of the empty test fixture), under anything else the pinned `sha384-...` literal for `rich_text.js`'s content is asserted instead.
- `test/importmap_test.rb:403-407` — same split for a `pin_all_from`-expanded file's dynamically calculated integrity (`sha256-6yWqFiaT8vQURc/OiKuIrEv9e/y4DMV/7nh7s5o3svA=` for sprockets vs a `sha384-...` value otherwise).

Both cases exist because `resolver.asset_integrity` (called from `map.rb:261`) is implemented differently per pipeline — Sprockets computes SHA-256 over the compiled asset, the alternative path (Propshaft, per `CLAUDE.md`'s note that Propshaft integrity needs `config.assets.integrity_hash_algorithm` configured) produces SHA-384 — `Importmap::Map` itself is agnostic and just forwards whatever the resolver returns.

## Invariants and contracts

- A pin's `preload` and `integrity` survive to the final `to_json`/`preloaded_module_packages` output unless integrity is globally disabled — `test/importmap_test.rb:44-51` ("integrity is not on by default"), `:65-79` (`false`/`nil` explicitly disable it), `:81-92` (a custom string is passed through verbatim).
- A pin whose local asset can't be resolved is silently dropped from `imports` and `integrity`, never raises — `test/importmap_test.rb:94-96`, `:167-176`, `:379-391`, backed by `map.rb:222-233`'s rescue of `rescuable_asset_error?`.
- A remote (`https://...`) pin's path passes through `to_json` unchanged, never digest-stamped — `test/importmap_test.rb:98-100`.
- `pin_all_from` directory expansion honours `under:`/`to:`, treats a bare `index` file as the directory's own module, and does not treat `*_index` files the same way, at any nesting depth — `test/importmap_test.rb:102-131`.
- A filename containing `js` as a substring but not a `.js`/`.jsm` extension is excluded; one that legitimately ends `.jszip`/`.jsmin` is *not* mistaken for `.js` — `test/importmap_test.rb:137-146`, `map.rb:312-313`'s glob `**/*.js{,m}`.
- `preload:` accepts `true`/`false` (always/never) or a string/array naming entry points, and `preloaded_module_paths`/`preloaded_module_packages` filter accordingly — `test/importmap_test.rb:203-328`, `map.rb:267-269`.
- `digest` is a 40-character hex SHA1 of the resolved JSON — `test/importmap_test.rb:232-234`.
- Every cache is keyed by `cache_key` and invalidated in full by any `pin`/`pin_all_from`/`draw`/`enable_integrity!` call — `test/importmap_test.rb:236-256`, `:357-377`, via `map.rb:200-210`.
- An invalid `config/importmap.rb` raises `Importmap::Map::InvalidFile` rather than a bare `StandardError` — `test/importmap_test.rb:195-201`, `map.rb:24-27`.
- A file-watcher change to a watched `config/importmap.rb` path is picked up by `Reloader#execute_if_updated`/`reload!`, replacing the app's pinned packages in place — `test/reloader_test.rb:9-23`.
- Inline importmap, preload links and the entrypoint's module import all carry the request's CSP nonce, and are nonce-free when no CSP is configured — `test/importmap_tags_helper_test.rb:52-68`.
- `javascript_importmap_tags` accepts an alternate `importmap:` instance instead of `Rails.application.importmap`, and its output correctly reflects that instance's own pins/preloads — `test/importmap_tags_helper_test.rb:70-82`.

## Request sequence

```mermaid
sequenceDiagram
    participant Browser
    participant Controller as ActionController (before_action)
    participant View as View / Helper
    participant Map as Importmap::Map
    participant Resolver as Asset resolver (Sprockets/Propshaft)

    Browser->>Controller: GET page
    Note over Controller: engine.rb before_action (dev/test only)
    Controller->>Map: cache_sweeper.execute_if_updated
    Map-->>Controller: clears @cache if app/javascript or vendor/javascript changed
    Controller->>View: render
    View->>Map: javascript_importmap_tags -> to_json(resolver: self)
    Map->>Map: cache_as(:json) { expand pins+dirs }
    Map->>Resolver: path_to_asset(path) per package
    Resolver-->>Map: resolved URL or raises (rescued if in rescuable_asset_errors)
    Map->>Resolver: asset_integrity(path) per package (if enable_integrity!)
    Resolver-->>Map: integrity hash
    Map-->>View: pretty JSON {imports, integrity}
    View->>Map: preloaded_module_packages(resolver: self, entry_point:)
    Map-->>View: {resolved_path => MappedFile} filtered by preload
    View-->>Controller: <script type=importmap>, <link rel=modulepreload>*, <script type=module>
    Controller->>Map: stale_when_importmap_changes -> digest(resolver: helpers)
    Map-->>Controller: SHA1(to_json) for ETag (html format only)
    Controller-->>Browser: response with ETag
```

## Related

- [../packager/summary.md](../packager/summary.md)
- [../cli/summary.md](../cli/summary.md)
- [../lode-map.md](../lode-map.md)
