# frozen_string_literal: true

# Version locks: pin --lock, lock/unlock, and what every command does with a
# locked package.
class Views::Docs::Pages::Locking < DocsUI::Page
  title "Locking versions"
  eyebrow "Vendoring"

  def lead = "Hold a package at a version. update, pristine and pin leave it there until you say otherwise."

  def content
    why
    locking
    what_commands_do
    moving_a_locked_package
    outdated_and_locks
  end

  private

  def why
    DocsUI::Section("Why") do
      md <<~'MD'
        Some packages you want to hold: a major you haven't migrated to yet, a
        release that broke something, a dependency whose author moves fast. With
        importmap-rails the only way to keep `update` off a package was to remember
        not to run it. A lock is that intent, written down where the tooling reads
        it.
      MD
    end
  end

  def locking
    DocsUI::Section("Locking a package") do
      md <<~'MD'
        Pass `--lock` when pinning, or lock a package already pinned. Either way the
        lock lands in the pin comment:
      MD
      DocsUI::Code(<<~SHELL, lexer: :console)
        $ ./bin/importmap pin luxon@3.7.2 --lock
        Pinning "luxon" to vendor/javascript/luxon.js via download from https://ga.jspm.io/npm:luxon@3.7.2/build/es6/luxon.mjs
        Locked "luxon" at 3.7.2

        $ ./bin/importmap lock @hotwired/stimulus
        Locked "@hotwired/stimulus" at 3.2.2

        $ ./bin/importmap unlock luxon
        Unlocked "luxon"
      SHELL
      DocsUI::Code(<<~RUBY, filename: "config/importmap.rb")
        pin "luxon" # @3.7.2 (locked)
        pin "@hotwired/stimulus", to: "@hotwired--stimulus.js" # @3.2.2 (esm.run, locked)
        pin "md5", to: "https://cdn.jsdelivr.net/npm/md5@2.2.0/md5.js", preload: false # @2.2.0 (locked)
      RUBY
      md <<~'MD'
        `lock` and `unlock` rewrite only the comment — no network, nothing else on
        the line is touched, single quotes and all. A remote pin gets a version
        comment carrying the version from its URL. A pin with no version to lock at
        (a custom URL, a local file) is refused with a message. To lock at a
        different version than the one pinned, pin that version:
        `bin/importmap pin luxon@3.6.0 --lock`.

        Only the packages you name are locked. The dependencies a CDN resolves
        alongside them keep floating, so `pin md5 --lock` locks `md5` and leaves
        `charenc` and `crypt` to `update`.
      MD
    end
  end

  def what_commands_do
    DocsUI::Section("What each command does with a lock") do
      DocsUI::Table(
        [ "Command", "Locked package" ],
        [
          [ [ :code, "update" ], [ :md, "Skipped, with a note. `update --force` updates it and keeps the lock at the new version." ] ],
          [ [ :code, "pin luxon" ], [ :md, "Skipped before any network call. `--force`, `--lock` or `--no-lock` proceed (see below)." ] ],
          [ [ :code, "pristine" ], [ :md, "Redownloaded at the locked version; the lock stays. A CDN that resolves a different version than the one locked is skipped, with both versions in the message." ] ],
          [ [ :code, "outdated" ], "Listed with yes in the Locked column; doesn't make the command exit 1." ],
          [ [ :code, "pin stimulus-use --from esm.run" ], "A locked dependency pin the bundle needs is kept as-is, like any existing pin." ],
          [ [ :code, "unpin" ], "Removed, lock included — explicit intent." ],
          [ [ :code, "audit" ], "Unaffected." ]
        ]
      )
      DocsUI::Code(<<~SHELL, lexer: :console)
        $ ./bin/importmap pin luxon@4.0.0
        Skipping "luxon" (locked at 3.7.2; run bin/importmap unlock luxon or pass --force)

        $ ./bin/importmap update
        Skipping "luxon" (locked at 3.7.2; run bin/importmap unlock luxon or pass --force)
        Nothing to update (every outdated package is locked; pass --force)
      SHELL
    end
  end

  def moving_a_locked_package
    DocsUI::Section("Moving a locked package") do
      DocsUI::Table(
        [ "Command", "Result" ],
        [
          [ [ :code, "pin luxon@4.0.0 --force" ], "Re-pins and keeps the lock, now at 4.0.0." ],
          [ [ :code, "pin luxon@4.0.0 --lock" ], "The same — the lock moves with the pin." ],
          [ [ :code, "pin luxon@4.0.0 --no-lock" ], "Re-pins and drops the lock." ],
          [ [ :code, "update --force" ], "Updates every outdated package, locked ones included, and re-locks each at its new version." ],
          [ [ :code, "unlock luxon" ], "Removes the lock; the next update moves the package." ]
        ]
      )
      md <<~'MD'
        The lock survives a move on purpose: "don't drift" is the intent, and moving
        deliberately to a new version doesn't change it.
      MD
    end
  end

  def outdated_and_locks
    DocsUI::Section("outdated and CI") do
      md <<~'MD'
        `outdated` still lists a locked package that has a newer version, so you can
        see what you are holding back, but a lock is a version the app chose, not
        drift. The command exits 1 only when an *unlocked* package is outdated, so a
        CI step that runs it stays green for what you locked.
      MD
      DocsUI::Code(<<~SHELL, lexer: :console)
        $ ./bin/importmap outdated
        | Package | Current | Latest | Locked |
        |---------|---------|--------|--------|
        | luxon   | 3.7.2   | 3.7.3  | yes    |
        | md5     | 2.2.0   | 2.3.0  |        |
          2 outdated packages found (1 locked)
      SHELL
    end
  end
end
