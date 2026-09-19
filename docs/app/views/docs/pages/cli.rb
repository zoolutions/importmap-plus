# frozen_string_literal: true

# Every bin/importmap command and option on one page.
class Views::Docs::Pages::Cli < DocsUI::Page
  title "CLI reference"
  eyebrow "Reference"

  def lead = "Every bin/importmap command, its options, and its exit status."

  def content
    commands
    pin_options
    update_options
    pristine_options
    doctor_options
    exit_codes
  end

  private

  def commands
    DocsUI::Section("Commands") do
      DocsUI::Table(
        [ "Command", "What it does", "Docs" ],
        [
          [ [ :code, "pin [PACKAGES]" ], "Resolves each package's version on the npm registry and the package itself on a CDN, downloads it to vendor/javascript with the sibling files it imports (or pins the URL, with --remote or because the download can't stand alone) and writes the pin.", [ :md, "[Pinning](/docs/pinning)" ] ],
          [ [ :code, "unpin [PACKAGES]" ], "Removes the pin, the vendored file and the graph directory it maps.", [ :md, "[Pinning](/docs/pinning)" ] ],
          [ [ :code, "lock [PACKAGES]" ], "Marks the pins as locked at their current version. No network.", [ :md, "[Locking](/docs/locking)" ] ],
          [ [ :code, "unlock [PACKAGES]" ], "Removes the lock marker. No network.", [ :md, "[Locking](/docs/locking)" ] ],
          [ [ :code, "update [PACKAGES]" ], "Re-pins the outdated packages: the named ones, or every one.", [ :md, "[Updating](/docs/updating)" ] ],
          [ [ :code, "outdated" ], "Lists packages the registry has a newer version of.", [ :md, "[Updating](/docs/updating)" ] ],
          [ [ :code, "audit" ], "Lists known vulnerabilities for the pinned versions.", [ :md, "[Updating](/docs/updating)" ] ],
          [ [ :code, "pristine" ], "Redownloads every vendored package at its pinned version, graph directories and all. Reports the packages it couldn't restore and exits non-zero.", [ :md, "[Updating](/docs/updating)" ] ],
          [ [ :code, "packages" ], "Prints every package with a version, one per line.", [ :md, "[Updating](/docs/updating)" ] ],
          [ [ :code, "json" ], "Boots the app and prints the resolved import map as JSON.", [ :md, "[Updating](/docs/updating)" ] ],
          [ [ :code, "doctor" ], "Boots the app and checks the import map and the vendored files against what is on disk. Offline unless you pass --online. Exits non-zero on any error.", [ :md, "[Updating](/docs/updating)" ] ]
        ]
      )
      md <<~'MD'
        A package spec is `name[@version][/subpath]`: `react`, `luxon@3`,
        `luxon@3.7.2`, `apexcharts/core`, `@hotwired/stimulus@3`. `lock` and
        `unlock` take names only.

        When `pin` is given a spec with no version, it is resolved against the npm
        registry first, then asked of jspm, `esm.run` and jsDelivr in turn until one
        of them has it. See [Pinning](/docs/pinning).
      MD
    end
  end

  def pin_options
    DocsUI::Section("pin options") do
      DocsUI::PropTable(
        [
          [ [ :code, "--from CDN" ], "String", "the pin's CDN, else jspm then esm.run then jsdelivr", "jspm, unpkg, jsdelivr, esm.sh, skypack or esm.run. Naming one turns off the fallback chain: that CDN is asked once. Also moves a remote pin to that CDN." ],
          [ [ :code, "--remote" ], "Boolean", "false", "Pin the resolved URL instead of vendoring a download; converts a vendored pin." ],
          [ [ :code, "--integrity / --no-integrity" ], "Boolean", "true", "Fetch a pin that stays remote to write a subresource-integrity hash of it. --no-integrity skips the fetch; integrity: false on the pin turns it off for good. Vendored downloads are unaffected." ],
          [ [ :code, "--vendor" ], "Boolean", "what the pin says", "Download the entry file on its own even when it looks like it needs siblings beside it, dropping the graph directory it had; converts a pin that was kept remote. Applies only to the packages you name, not the dependencies resolved with them, and --remote wins if you pass both. Recorded on the pin." ],
          [ [ :code, "--minify / --no-minify" ], "Boolean", "what the pin says", "Run the download through bun, esbuild or terser. Recorded on the pin." ],
          [ [ :code, "--lock / --no-lock" ], "Boolean", "what the pin says", "Lock the named packages at this version, or drop their lock. Dependencies are never locked." ],
          [ [ :code, "--force" ], "Boolean", "false", "Re-pin locked packages, keeping each lock at the new version." ],
          [ [ :code, "--preload VALUE" ], "String, repeatable", "the pin's preload", "true, false, or an entry point name; repeat for several entry points." ],
          [ [ :code, "--env ENV" ], "String", "production", "The jspm environment condition (production or development)." ]
        ],
        headers: [ "Option", "Type", "Default", "Description" ]
      )
    end
  end

  def update_options
    DocsUI::Section("update options") do
      DocsUI::PropTable(
        [
          [ [ :code, "--all" ], "Boolean", "false", "Update every outdated package — what a bare update does; rejected together with names." ],
          [ [ :code, "--force" ], "Boolean", "false", "Update locked packages too, keeping each lock at the new version." ]
        ],
        headers: [ "Option", "Type", "Default", "Description" ]
      )
    end
  end

  def pristine_options
    DocsUI::Section("pristine options") do
      DocsUI::PropTable(
        [
          [ [ :code, "--from CDN" ], "String", "each pin's CDN", "Redownload everything from this CDN and record it on each pin." ],
          [ [ :code, "--minify / --no-minify" ], "Boolean", "what each pin says", "Minify every download, or none, and record it." ],
          [ [ :code, "--env ENV" ], "String", "production", "The jspm environment condition." ]
        ],
        headers: [ "Option", "Type", "Default", "Description" ]
      )
    end
  end

  def doctor_options
    DocsUI::Section("doctor options") do
      DocsUI::PropTable(
        [
          [ [ :code, "--online" ], "Boolean", "false", "Also fetch every remote pin, reporting one the CDN no longer serves and an integrity: hash that doesn't match the bytes it served. Every other check reads only the map and the files on disk." ]
        ],
        headers: [ "Option", "Type", "Default", "Description" ]
      )
    end
  end

  def exit_codes
    DocsUI::Section("Exit status") do
      DocsUI::Table(
        [ "Command", "Exits 1 when" ],
        [
          [ [ :code, "outdated" ], "an unlocked package is outdated" ],
          [ [ :code, "audit" ], "a vulnerability is known for a pinned version" ],
          [ [ :code, "pin / update" ], "a package was skipped — its directory is in the way, or its CDN failed partway through a crawl — while the rest were pinned; the skipped pin is left exactly as it was" ],
          [ [ :code, "pin / update / pristine" ], "no CDN could resolve a package, its reason printed; the packages that did resolve are still written" ],
          [ [ :code, "update" ], "a named package has no pin, or names are combined with --all; nothing is updated in either case" ],
          [ [ :code, "pristine" ], "a package couldn't be restored the way its pin describes, or a dependency of an esm.run bundle was skipped; the rest are restored" ],
          [ [ :code, "lock / unlock" ], "a named package has no pin, has no version to lock at, or was given with a version" ],
          [ [ :code, "doctor" ], "any finding is an error; warnings alone exit 0" ],
          [ "any", "a CDN or registry request fails after three attempts; the message names the URL" ]
        ]
      )
    end
  end
end
