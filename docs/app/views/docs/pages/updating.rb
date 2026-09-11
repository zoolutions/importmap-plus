# frozen_string_literal: true

# update, outdated, audit, pristine, packages and json — keeping what is
# vendored current and inspecting it.
class Views::Docs::Pages::Updating < DocsUI::Page
  title "Updating & auditing"
  eyebrow "Vendoring"

  def lead = "Update by name or all at once, see what is outdated, check the registry for advisories, and redownload what you have."

  def content
    update
    outdated
    audit
    pristine
    inspecting
  end

  private

  def update
    DocsUI::Section("update") do
      md <<~'MD'
        `bin/importmap update` asks the npm registry for the latest version of every
        package with a version in `config/importmap.rb` and re-pins the outdated
        ones. Name packages to update just those, or pass `--all` to say explicitly
        that you mean everything:
      MD
      DocsUI::Code(<<~SHELL, lexer: :shell)
        ./bin/importmap update                      # everything outdated, as importmap-rails does
        ./bin/importmap update luxon stimulus-use   # just those
        ./bin/importmap update --all                # everything, explicitly
        ./bin/importmap update --force              # locked packages too, re-locked at their new version
      SHELL
      md <<~'MD'
        A named package that isn't outdated, or has no version to compare, is
        reported and left alone. A name with no pin at all stops the command before
        anything is updated — a typo shouldn't half-update an import map. Names
        together with `--all` are rejected.

        A package is re-resolved together with the dependencies its CDN lists for it,
        so those move as well, keeping their own pin options. Each package comes back
        from the CDN its pin comment names ([Provenance](/docs/provenance)); a remote
        pin is re-resolved from its provider and stays remote; a
        [locked](/docs/locking) package is skipped unless you pass `--force`.
      MD
      DocsUI::Code(<<~SHELL, lexer: :console)
        $ ./bin/importmap update md5 nope
        Couldn't find a pin for "nope"

        $ ./bin/importmap update md5 application
        "md5" is already up to date (2.3.0)
        Can't tell whether "application" is outdated: its pin has no version
        No outdated packages found
      SHELL
    end
  end

  def outdated
    DocsUI::Section("outdated") do
      md <<~'MD'
        `outdated` checks the registry and prints a table. It exits 1 when an
        unlocked package is outdated, so it works as a CI check; locked packages are
        shown but don't fail it.
      MD
      DocsUI::Code(<<~SHELL, lexer: :console)
        $ ./bin/importmap outdated
        | Package | Current | Latest | Locked |
        |---------|---------|--------|--------|
        | luxon   | 3.7.2   | 3.7.3  | yes    |
        | md5     | 2.2.0   | 2.3.0  |        |
          2 outdated packages found (1 locked)
      SHELL
      md <<~'MD'
        Both `outdated` and `update` only see pins with a version: a `# @x.y.z`
        comment or a CDN URL with `@x.y.z` in it. A vendored file whose pin has no
        version is reported as ignored.
      MD
    end
  end

  def audit
    DocsUI::Section("audit") do
      md <<~'MD'
        `audit` sends every pinned package and version to the npm registry's
        advisory endpoint and prints the vulnerabilities it knows about, exiting 1
        if there are any:
      MD
      DocsUI::Code(<<~SHELL, lexer: :console)
        $ ./bin/importmap audit
        | Package | Severity | Vulnerable versions | Vulnerability                    |
        |---------|----------|---------------------|----------------------------------|
        | md5     | high     | <42.0.0             | Unsafe hashing                   |
          1 vulnerability found: 1 high
      SHELL
    end
  end

  def pristine
    DocsUI::Section("pristine") do
      md <<~'MD'
        `pristine` redownloads every vendored package at the version it is pinned at
        — after a bad merge, a corrupted file, or to move everything to another CDN
        or minify it all:
      MD
      DocsUI::Code(<<~SHELL, lexer: :shell)
        ./bin/importmap pristine
        ./bin/importmap pristine --from esm.run   # move every vendored package to esm.run
        ./bin/importmap pristine --minify         # minify everything vendored
      SHELL
      md <<~'MD'
        Remote pins are skipped, since there is nothing to redownload. A `--from` or
        `--minify` that changes a package's provenance is recorded on its pin, so the
        next `update` keeps it.
      MD
    end
  end

  def inspecting
    DocsUI::Section("packages and json") do
      md <<~'MD'
        `packages` lists every package with a version, one per line. `json` boots
        the app and prints the import map exactly as `javascript_importmap_tags`
        would render it, resolved through the asset pipeline:
      MD
      DocsUI::Code(<<~SHELL, lexer: :console)
        $ ./bin/importmap packages
        luxon 3.7.2
        md5 2.2.0

        $ ./bin/importmap json
        {
          "imports": {
            "application": "/assets/application-abc123.js",
            "luxon": "/assets/luxon-def456.js"
          }
        }
      SHELL
    end
  end
end
