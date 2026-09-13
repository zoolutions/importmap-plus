require "test_helper"
require "json"

class CommandsTest < ActiveSupport::TestCase
  include ActiveSupport::Testing::Isolation

  setup do
    @tmpdir = Dir.mktmpdir
    FileUtils.cp_r("#{__dir__}/dummy", @tmpdir)
    Dir.chdir("#{@tmpdir}/dummy")
  end

  teardown do
    FileUtils.remove_entry(@tmpdir) if @tmpdir
  end

  test "json command prints JSON with imports" do
    out, _err = run_importmap_command("json")

    assert_includes JSON.parse(out), "imports"
  end

  test "update command prints message of no outdated packages" do
    out, _err = run_importmap_command("update")

    assert_includes out, "No outdated"
  end

  test "update command prints confirmation of pin with outdated packages" do
    FileUtils.cp("#{__dir__}/fixtures/files/outdated_import_map.rb", "#{@tmpdir}/dummy/config/importmap.rb")

    out, _err = run_importmap_command("update")

    assert_includes out, "Pinning"
  end

  test "pristine command redownloads all pinned packages" do
    importmap_config("")

    out, _err = run_importmap_command("pin", "md5@2.2.0")

    assert_includes out, 'Pinning "md5" to vendor/javascript/md5.js via download from https://ga.jspm.io/npm:md5@2.2.0/md5.js'

    original = File.read("#{@tmpdir}/dummy/vendor/javascript/md5.js")
    File.write("#{@tmpdir}/dummy/vendor/javascript/md5.js", "corrupted")

    out, _err = run_importmap_command("pristine")

    assert_includes out, 'Downloading "md5" to vendor/javascript/md5.js from https://ga.jspm.io/npm:md5@2.2.0'
    assert_equal original, File.read("#{@tmpdir}/dummy/vendor/javascript/md5.js")
  end

  test "update command preserves preload false option" do
    importmap_config('pin "md5", to: "https://cdn.jsdelivr.net/npm/md5@2.2.0/md5.js", preload: false')

    out, _err = run_importmap_command("update")

    assert_includes out, "Pinning"

    updated_content = File.read("#{@tmpdir}/dummy/config/importmap.rb")
    assert_includes updated_content, 'pin "md5", to: "https://cdn.jsdelivr.net/npm/md5@2.3.0/md5.js", preload: false'
    assert_not_includes updated_content, "md5@2.2.0"
    assert_not File.exist?("#{@tmpdir}/dummy/vendor/javascript/md5.js")
  end

  test "update command preserves preload true option" do
    importmap_config('pin "md5", to: "https://cdn.jsdelivr.net/npm/md5@2.2.0/md5.js", preload: true')

    out, _err = run_importmap_command("update")

    assert_includes out, "Pinning"

    updated_content = File.read("#{@tmpdir}/dummy/config/importmap.rb")
    assert_includes updated_content, 'pin "md5", to: "https://cdn.jsdelivr.net/npm/md5@2.3.0/md5.js", preload: true'
  end

  test "update command preserves custom preload string option" do
    importmap_config('pin "md5", to: "https://cdn.jsdelivr.net/npm/md5@2.2.0/md5.js", preload: "custom"')

    out, _err = run_importmap_command("update")

    assert_includes out, "Pinning"

    updated_content = File.read("#{@tmpdir}/dummy/config/importmap.rb")
    assert_includes updated_content, 'pin "md5", to: "https://cdn.jsdelivr.net/npm/md5@2.3.0/md5.js", preload: "custom"'
  end

  test "update command removes existing integrity" do
    importmap_config('pin "md5", to: "https://cdn.jsdelivr.net/npm/md5@2.2.0/md5.js", integrity: "sha384-oldintegrity"')

    out, _err = run_importmap_command("update")

    assert_includes out, "Pinning"

    updated_content = File.read("#{@tmpdir}/dummy/config/importmap.rb")
    assert_not_includes updated_content, "integrity:"
  end

  test "update command keeps pin remote and preload option but drops integrity" do
    importmap_config('pin "md5", to: "https://cdn.jsdelivr.net/npm/md5@2.2.0/md5.js", preload: false, integrity: "sha384-oldintegrity"')

    out, _err = run_importmap_command("update")

    assert_includes out, "Pinning"

    updated_content = File.read("#{@tmpdir}/dummy/config/importmap.rb")
    assert_includes updated_content, 'pin "md5", to: "https://cdn.jsdelivr.net/npm/md5@2.3.0/md5.js", preload: false'
    assert_not_includes updated_content, "integrity:"
  end

  test "update command preserves a boolean integrity option" do
    importmap_config('pin "md5", to: "https://cdn.jsdelivr.net/npm/md5@2.2.0/md5.js", preload: false, integrity: false')

    out, _err = run_importmap_command("update")

    assert_includes out, "Pinning"

    updated_content = File.read("#{@tmpdir}/dummy/config/importmap.rb")
    assert_includes updated_content, 'pin "md5", to: "https://cdn.jsdelivr.net/npm/md5@2.3.0/md5.js", preload: false, integrity: false'
  end

  test "update command handles packages with different quote styles" do
    importmap_config("pin 'md5', to: 'https://cdn.jsdelivr.net/npm/md5@2.2.0/md5.js', preload: false")

    out, _err = run_importmap_command("update")

    assert_includes out, "Pinning"

    updated_content = File.read("#{@tmpdir}/dummy/config/importmap.rb")
    assert_includes updated_content, "preload: false"
    assert_includes updated_content, "md5@2.3.0"
  end

  test "update command preserves options with version comments" do
    importmap_config('pin "md5", to: "https://cdn.jsdelivr.net/npm/md5@2.2.0/md5.js", preload: false # @2.2.0')

    out, _err = run_importmap_command("update")

    assert_includes out, "Pinning"

    updated_content = File.read("#{@tmpdir}/dummy/config/importmap.rb")
    assert_includes updated_content, "preload: false"
    assert_includes updated_content, "md5@2.3.0"
    assert_not_includes updated_content, "2.2.0"
  end

  test "update command handles whitespace variations in pin options" do
    importmap_config('pin "md5",   to:  "https://cdn.jsdelivr.net/npm/md5@2.2.0/md5.js",  preload:  false   ')

    out, _err = run_importmap_command("update")

    assert_includes out, "Pinning"

    updated_content = File.read("#{@tmpdir}/dummy/config/importmap.rb")
    assert_equal 4, updated_content.lines.size
    assert_includes updated_content, "preload: false"
  end

  test "pin command with --remote pins to the resolved URL without downloading" do
    importmap_config("")

    out, _err = run_importmap_command("pin", "md5@2.2.0", "--remote")

    assert_includes out, 'Pinning "md5" to https://ga.jspm.io/npm:md5@2.2.0/md5.js'

    content = File.read("#{@tmpdir}/dummy/config/importmap.rb")
    assert_includes content, 'pin "md5", to: "https://ga.jspm.io/npm:md5@2.2.0/md5.js"'
    assert_not File.exist?("#{@tmpdir}/dummy/vendor/javascript/md5.js")
  end

  test "pin command with --remote converts a vendored pin and removes the vendored file" do
    importmap_config("")

    run_importmap_command("pin", "md5@2.2.0")
    assert File.exist?("#{@tmpdir}/dummy/vendor/javascript/md5.js")

    run_importmap_command("pin", "md5@2.2.0", "--remote")

    content = File.read("#{@tmpdir}/dummy/config/importmap.rb")
    assert_includes content, 'pin "md5", to: "https://ga.jspm.io/npm:md5@2.2.0/md5.js"'
    assert_not File.exist?("#{@tmpdir}/dummy/vendor/javascript/md5.js")
  end

  test "pin command respects an existing remote pin and updates its URL" do
    importmap_config('pin "md5", to: "https://ga.jspm.io/npm:md5@2.2.0/md5.js", preload: false')

    out, _err = run_importmap_command("pin", "md5@2.3.0")

    assert_includes out, 'Pinning "md5" to https://ga.jspm.io/npm:md5@2.3.0/md5.js'

    content = File.read("#{@tmpdir}/dummy/config/importmap.rb")
    assert_includes content, 'pin "md5", to: "https://ga.jspm.io/npm:md5@2.3.0/md5.js", preload: false'
    assert_not File.exist?("#{@tmpdir}/dummy/vendor/javascript/md5.js")
  end

  test "pin command does not clobber options of dependency pins" do
    importmap_config(<<~PINS)
      pin "charenc", to: "https://ga.jspm.io/npm:charenc@0.0.2/charenc.js", preload: false
      pin "crypt", preload: false # @0.0.2
    PINS

    run_importmap_command("pin", "md5@2.3.0")

    content = File.read("#{@tmpdir}/dummy/config/importmap.rb")
    assert_includes content, 'pin "charenc", to: "https://ga.jspm.io/npm:charenc@0.0.2/charenc.js", preload: false'
    assert_includes content, 'pin "crypt", preload: false # @0.0.2'
  end

  test "pin command leaves pins to custom URLs untouched" do
    importmap_config('pin "md5", to: "https://cdn.example.com/md5.js", preload: false')

    out, _err = run_importmap_command("pin", "md5@2.3.0")

    assert_includes out, 'Skipping "md5" pinned to custom URL https://cdn.example.com/md5.js'

    content = File.read("#{@tmpdir}/dummy/config/importmap.rb")
    assert_includes content, 'pin "md5", to: "https://cdn.example.com/md5.js", preload: false'
    assert_not File.exist?("#{@tmpdir}/dummy/vendor/javascript/md5.js")
  end

  test "pristine command skips packages pinned to remote URLs" do
    importmap_config('pin "md5", to: "https://ga.jspm.io/npm:md5@2.2.0/md5.js"')

    out, _err = run_importmap_command("pristine")

    assert_includes out, 'Skipping "md5" (pinned to remote URL)'
    assert_not File.exist?("#{@tmpdir}/dummy/vendor/javascript/md5.js")
  end

  test "pin command with --from esm.run vendors the bundle and pins the dependencies it imports" do
    importmap_config("")

    out, _err = run_importmap_command("pin", "md5@2.2.0", "--from", "esm.run")

    assert_includes out, 'Pinning "md5" to vendor/javascript/md5.js via download from https://cdn.jsdelivr.net/npm/md5@2.2.0/+esm'
    assert_includes out, 'Pinning "charenc" to vendor/javascript/charenc.js via download from https://cdn.jsdelivr.net/npm/charenc@0.0.1/+esm'

    content = File.read("#{@tmpdir}/dummy/config/importmap.rb")
    assert_includes content, 'pin "md5" # @2.2.0 (esm.run)'
    assert_includes content, 'pin "charenc" # @0.0.1 (esm.run)'
    assert_includes content, 'pin "crypt" # @0.0.1 (esm.run)'
    assert_includes content, 'pin "is-buffer" # @1.1.4 (esm.run)'

    vendored = File.read("#{@tmpdir}/dummy/vendor/javascript/md5.js")
    assert_equal "// md5@2.2.0 downloaded from https://cdn.jsdelivr.net/npm/md5@2.2.0/+esm", vendored.lines.first.strip
    assert_includes vendored, %(from"charenc")
    assert_no_match %r{["']/npm/}, vendored
    assert File.exist?("#{@tmpdir}/dummy/vendor/javascript/charenc.js")
  end

  test "pin command with --from esm.run keeps dependency pins the app already has" do
    importmap_config('pin "charenc", to: "https://ga.jspm.io/npm:charenc@0.0.2/charenc.js", preload: false')

    out, _err = run_importmap_command("pin", "md5@2.2.0", "--from", "esm.run")

    assert_includes out, 'Keeping existing pin for "charenc" (bundle was built against @0.0.1)'

    content = File.read("#{@tmpdir}/dummy/config/importmap.rb")
    assert_includes content, 'pin "charenc", to: "https://ga.jspm.io/npm:charenc@0.0.2/charenc.js", preload: false'
    assert_not File.exist?("#{@tmpdir}/dummy/vendor/javascript/charenc.js")
  end

  test "pin command with --from esm.run pins a shared dependency once" do
    importmap_config("")

    out, _err = run_importmap_command("pin", "stimulus-use@0.53.1", "stimulus-autocomplete@3.1.0", "--from", "esm.run")

    assert_includes out, 'Pinning "@hotwired/stimulus"'
    assert_includes out, 'Keeping existing pin for "@hotwired/stimulus"'

    content = File.read("#{@tmpdir}/dummy/config/importmap.rb")
    assert_equal 1, content.scan(/^pin "@hotwired\/stimulus"/).size
  end

  test "pin command with an explicit --from moves a remote pin to that CDN" do
    importmap_config('pin "md5", to: "https://ga.jspm.io/npm:md5@2.2.0/md5.js", preload: false')

    out, _err = run_importmap_command("pin", "md5@2.2.0", "--from", "unpkg")

    assert_includes out, 'Pinning "md5" to https://unpkg.com/md5@2.2.0/md5.js'

    content = File.read("#{@tmpdir}/dummy/config/importmap.rb")
    assert_includes content, 'pin "md5", to: "https://unpkg.com/md5@2.2.0/md5.js", preload: false'
    assert_not File.exist?("#{@tmpdir}/dummy/vendor/javascript/md5.js")
  end

  test "pristine command with --from records the new CDN in the pin" do
    importmap_config("")
    run_importmap_command("pin", "md5@2.2.0")
    assert_includes File.read("#{@tmpdir}/dummy/config/importmap.rb"), 'pin "md5" # @2.2.0'

    out, _err = run_importmap_command("pristine", "--from", "esm.run")

    assert_includes out, 'Downloading "md5" to vendor/javascript/md5.js from https://cdn.jsdelivr.net/npm/md5@2.2.0/+esm'

    content = File.read("#{@tmpdir}/dummy/config/importmap.rb")
    assert_includes content, 'pin "md5" # @2.2.0 (esm.run)'

    out, _err = run_importmap_command("update")

    assert_includes out, "https://cdn.jsdelivr.net/npm/md5@2.3.0/+esm"
  end

  test "pin command with --from esm.run and --remote pins the bundle URL without downloading" do
    importmap_config("")

    out, _err = run_importmap_command("pin", "md5@2.2.0", "--from", "esm.run", "--remote")

    assert_includes out, 'Pinning "md5" to https://cdn.jsdelivr.net/npm/md5@2.2.0/+esm'

    content = File.read("#{@tmpdir}/dummy/config/importmap.rb")
    assert_includes content, 'pin "md5", to: "https://cdn.jsdelivr.net/npm/md5@2.2.0/+esm"'
    assert_not_includes content, "charenc"
    assert_not File.exist?("#{@tmpdir}/dummy/vendor/javascript/md5.js")
  end

  test "update command keeps a package vendored from esm.run on esm.run" do
    importmap_config("")
    run_importmap_command("pin", "md5@2.2.0", "--from", "esm.run")

    out, _err = run_importmap_command("update")

    assert_includes out, 'Pinning "md5" to vendor/javascript/md5.js via download from https://cdn.jsdelivr.net/npm/md5@2.3.0/+esm'
    assert_includes File.read("#{@tmpdir}/dummy/vendor/javascript/md5.js"), %(from"charenc")
  end

  test "pin command keeps a subpath package on its CDN when the spec carries a version" do
    importmap_config("")
    run_importmap_command("pin", "md5@2.2.0", "--from", "esm.run")

    out, _err = run_importmap_command("pin", "md5@2.3.0")

    assert_includes out, "https://cdn.jsdelivr.net/npm/md5@2.3.0/+esm"
    assert_includes File.read("#{@tmpdir}/dummy/config/importmap.rb"), 'pin "md5" # @2.3.0 (esm.run)'
  end

  test "pristine command redownloads esm.run packages from esm.run" do
    importmap_config("")
    run_importmap_command("pin", "md5@2.2.0", "--from", "esm.run")

    original = File.read("#{@tmpdir}/dummy/vendor/javascript/md5.js")
    File.write("#{@tmpdir}/dummy/vendor/javascript/md5.js", "corrupted")

    out, _err = run_importmap_command("pristine")

    assert_includes out, 'Downloading "md5" to vendor/javascript/md5.js from https://cdn.jsdelivr.net/npm/md5@2.2.0/+esm'
    assert_equal original, File.read("#{@tmpdir}/dummy/vendor/javascript/md5.js")
  end

  test "pin command with --minify minifies the download and later pins keep minifying" do
    skip "no JavaScript minifier installed (bun, esbuild or terser)" unless minifier_available?
    importmap_config("")

    out, _err = run_importmap_command("pin", "md5@2.2.0", "--minify")

    assert_includes out, 'Pinning "md5" to vendor/javascript/md5.js via download from https://ga.jspm.io/npm:md5@2.2.0/md5.js (minified)'
    assert_equal "// md5@2.2.0 downloaded from https://ga.jspm.io/npm:md5@2.2.0/md5.js (minified)",
                 File.readlines("#{@tmpdir}/dummy/vendor/javascript/md5.js").first.strip
    assert_includes File.read("#{@tmpdir}/dummy/config/importmap.rb"), 'pin "md5" # @2.2.0 (minified)'
    assert_includes File.read("#{@tmpdir}/dummy/config/importmap.rb"), 'pin "charenc" # @0.0.2 (minified)'

    out, _err = run_importmap_command("pin", "md5@2.3.0")

    assert_includes out, 'https://ga.jspm.io/npm:md5@2.3.0/md5.js (minified)'
    assert_includes File.read("#{@tmpdir}/dummy/config/importmap.rb"), 'pin "md5" # @2.3.0 (minified)'

    out, _err = run_importmap_command("pin", "md5@2.3.0", "--no-minify")

    assert_not_includes out, "(minified)"
    assert_includes File.read("#{@tmpdir}/dummy/config/importmap.rb"), "pin \"md5\" # @2.3.0\n"
  end

  test "pristine command with --minify minifies every vendored package" do
    skip "no JavaScript minifier installed (bun, esbuild or terser)" unless minifier_available?
    importmap_config("")
    run_importmap_command("pin", "md5@2.2.0")

    unminified = File.read("#{@tmpdir}/dummy/vendor/javascript/md5.js")

    out, _err = run_importmap_command("pristine", "--minify")

    assert_includes out, 'Downloading "md5" to vendor/javascript/md5.js from https://ga.jspm.io/npm:md5@2.2.0/md5.js (minified)'
    minified = File.read("#{@tmpdir}/dummy/vendor/javascript/md5.js")
    assert_includes minified.lines.first, "(minified)"
    assert_operator minified.bytesize, :<, unminified.bytesize
    assert_includes File.read("#{@tmpdir}/dummy/config/importmap.rb"), 'pin "md5" # @2.2.0 (minified)'
  end

  test "pin command with --lock records the lock in the pin" do
    importmap_config("")

    out, _err = run_importmap_command("pin", "md5@2.2.0", "--lock")

    assert_includes out, 'Locked "md5" at 2.2.0'

    content = File.read("#{@tmpdir}/dummy/config/importmap.rb")
    assert_includes content, %(pin "md5" # @2.2.0 (locked)\n)
    assert_includes content, %(pin "charenc" # @0.0.2\n), "dependencies are not locked"
  end

  test "pin command with --lock and --remote locks the remote pin" do
    importmap_config("")

    out, _err = run_importmap_command("pin", "md5@2.2.0", "--lock", "--remote")

    assert_includes out, 'Locked "md5" at 2.2.0'
    assert_includes File.read("#{@tmpdir}/dummy/config/importmap.rb"),
                    %(pin "md5", to: "https://ga.jspm.io/npm:md5@2.2.0/md5.js" # @2.2.0 (locked)\n)
  end

  test "pin command skips a locked package" do
    importmap_config('pin "md5", to: "https://ga.jspm.io/npm:md5@2.2.0/md5.js" # @2.2.0 (locked)')

    out, _err = run_importmap_command("pin", "md5@2.3.0")

    assert_includes out, 'Skipping "md5" (locked at 2.2.0; run bin/importmap unlock md5 or pass --force)'
    assert_not_includes out, "Pinning"
    assert_includes File.read("#{@tmpdir}/dummy/config/importmap.rb"),
                    %(pin "md5", to: "https://ga.jspm.io/npm:md5@2.2.0/md5.js" # @2.2.0 (locked)\n)
  end

  test "pin command with --force re-pins a locked package and keeps the lock" do
    importmap_config('pin "md5", to: "https://ga.jspm.io/npm:md5@2.2.0/md5.js" # @2.2.0 (locked)')

    out, _err = run_importmap_command("pin", "md5@2.3.0", "--force")

    assert_includes out, 'Locked "md5" at 2.3.0'
    assert_includes File.read("#{@tmpdir}/dummy/config/importmap.rb"),
                    %(pin "md5", to: "https://ga.jspm.io/npm:md5@2.3.0/md5.js" # @2.3.0 (locked)\n)
  end

  test "pin command with --lock re-locks at the new version and --no-lock drops the lock" do
    importmap_config('pin "md5" # @2.2.0 (locked)')

    run_importmap_command("pin", "md5@2.3.0", "--lock")
    assert_includes File.read("#{@tmpdir}/dummy/config/importmap.rb"), %(pin "md5" # @2.3.0 (locked)\n)

    run_importmap_command("pin", "md5@2.3.0", "--no-lock")
    assert_includes File.read("#{@tmpdir}/dummy/config/importmap.rb"), %(pin "md5" # @2.3.0\n)
  end

  test "pin command with --from esm.run leaves a locked dependency pin alone" do
    importmap_config('pin "charenc" # @0.0.2 (locked)')

    out, _err = run_importmap_command("pin", "md5@2.2.0", "--from", "esm.run")

    assert_includes out, 'Keeping existing pin for "charenc"'
    assert_includes File.read("#{@tmpdir}/dummy/config/importmap.rb"), %(pin "charenc" # @0.0.2 (locked)\n)
  end

  test "pin command leaves a locked dependency pin alone" do
    importmap_config('pin "charenc" # @0.0.1 (locked)')

    out, _err = run_importmap_command("pin", "md5@2.2.0")

    assert_includes out, 'Pinning "md5"'
    assert_includes out, 'Keeping existing pin for "charenc" (locked at 0.0.1)'
    assert_includes File.read("#{@tmpdir}/dummy/config/importmap.rb"), %(pin "charenc" # @0.0.1 (locked)\n)
  end

  test "update command leaves a locked dependency pin alone" do
    importmap_config(<<~PINS)
      pin "md5" # @2.2.0
      pin "charenc" # @0.0.1 (locked)
    PINS

    out, _err = run_importmap_command("update")

    assert_includes out, 'Pinning "md5"'
    assert_includes out, 'Keeping existing pin for "charenc" (locked at 0.0.1)'
    assert_includes File.read("#{@tmpdir}/dummy/config/importmap.rb"), %(pin "charenc" # @0.0.1 (locked)\n)
  end

  test "lock command marks a vendored pin without downloading" do
    importmap_config('pin "md5" # @2.2.0 (esm.run)')

    out, _err = run_importmap_command("lock", "md5")

    assert_includes out, 'Locked "md5" at 2.2.0'
    assert_includes File.read("#{@tmpdir}/dummy/config/importmap.rb"), %(pin "md5" # @2.2.0 (esm.run, locked)\n)
    assert_not File.exist?("#{@tmpdir}/dummy/vendor/javascript/md5.js")

    out, _err = run_importmap_command("lock", "md5")

    assert_includes out, '"md5" is already locked at 2.2.0'
  end

  test "lock command adds a version comment to a remote pin" do
    importmap_config('pin "md5", to: "https://cdn.jsdelivr.net/npm/md5@2.2.0/md5.js", preload: false')

    run_importmap_command("lock", "md5")

    assert_includes File.read("#{@tmpdir}/dummy/config/importmap.rb"),
                    %(pin "md5", to: "https://cdn.jsdelivr.net/npm/md5@2.2.0/md5.js", preload: false # @2.2.0 (locked)\n)
  end

  test "lock command reports pins it can't lock" do
    importmap_config(<<~PINS)
      pin "custom", to: "https://cdn.example.com/custom.js"
      pin "md5" # @2.2.0
    PINS

    out, _err = run_importmap_command_expecting_failure("lock", "nope", "custom", "md5@2.3.0")

    assert_includes out, %(Couldn't find a pin for "nope")
    assert_includes out, %(Can't lock "custom": its pin has no version)
    assert_includes out, %(Use "bin/importmap pin md5@2.3.0 --lock" to lock at a different version)
    assert_includes File.read("#{@tmpdir}/dummy/config/importmap.rb"), %(pin "md5" # @2.2.0\n)
  end

  test "unlock command removes the marker" do
    importmap_config('pin "md5" # @2.2.0 (esm.run, locked)')

    out, _err = run_importmap_command("unlock", "md5")

    assert_includes out, 'Unlocked "md5"'
    assert_includes File.read("#{@tmpdir}/dummy/config/importmap.rb"), %(pin "md5" # @2.2.0 (esm.run)\n)

    out, _err = run_importmap_command("unlock", "md5")

    assert_includes out, %("md5" isn't locked)
  end

  test "update command skips locked packages" do
    importmap_config('pin "md5", to: "https://cdn.jsdelivr.net/npm/md5@2.2.0/md5.js", preload: true # @2.2.0 (locked)')

    out, _err = run_importmap_command("update")

    assert_includes out, 'Skipping "md5" (locked at 2.2.0; run bin/importmap unlock md5 or pass --force)'
    assert_includes out, "Nothing to update (every outdated package is locked; pass --force)"
    assert_includes File.read("#{@tmpdir}/dummy/config/importmap.rb"),
                    %(pin "md5", to: "https://cdn.jsdelivr.net/npm/md5@2.2.0/md5.js", preload: true # @2.2.0 (locked)\n)
  end

  test "update command with --force updates a locked package and keeps the lock" do
    importmap_config('pin "md5", to: "https://cdn.jsdelivr.net/npm/md5@2.2.0/md5.js", preload: true # @2.2.0 (locked)')

    out, _err = run_importmap_command("update", "--force")

    assert_includes out, 'Locked "md5" at 2.3.0'
    assert_includes File.read("#{@tmpdir}/dummy/config/importmap.rb"),
                    %(pin "md5", to: "https://cdn.jsdelivr.net/npm/md5@2.3.0/md5.js", preload: true # @2.3.0 (locked)\n)
  end

  test "update command with named packages updates only those" do
    importmap_config(<<~PINS)
      pin "md5", to: "https://cdn.jsdelivr.net/npm/md5@2.2.0/md5.js", preload: false
      pin "luxon", to: "https://cdn.jsdelivr.net/npm/luxon@3.0.0/build/es6/luxon.mjs"
    PINS

    out, _err = run_importmap_command("update", "md5")

    assert_includes out, 'Pinning "md5"'
    assert_not_includes out, "luxon"

    content = File.read("#{@tmpdir}/dummy/config/importmap.rb")
    assert_includes content, %(pin "md5", to: "https://cdn.jsdelivr.net/npm/md5@2.3.0/md5.js", preload: false\n)
    assert_includes content, %(pin "luxon", to: "https://cdn.jsdelivr.net/npm/luxon@3.0.0/build/es6/luxon.mjs"\n)
  end

  test "update command with --all updates every outdated package" do
    FileUtils.cp("#{__dir__}/fixtures/files/outdated_import_map.rb", "#{@tmpdir}/dummy/config/importmap.rb")

    out, _err = run_importmap_command("update", "--all")

    assert_includes out, 'Pinning "md5"'
    assert_includes File.read("#{@tmpdir}/dummy/config/importmap.rb"), "md5@2.3.0"
  end

  test "update command rejects names together with --all" do
    FileUtils.cp("#{__dir__}/fixtures/files/outdated_import_map.rb", "#{@tmpdir}/dummy/config/importmap.rb")

    out, _err = run_importmap_command_expecting_failure("update", "md5", "--all")

    assert_includes out, "Pass package names or --all, not both"
    assert_includes File.read("#{@tmpdir}/dummy/config/importmap.rb"), "md5@2.2.0"
  end

  test "update command reports a named package that isn't pinned and updates nothing" do
    FileUtils.cp("#{__dir__}/fixtures/files/outdated_import_map.rb", "#{@tmpdir}/dummy/config/importmap.rb")

    out, _err = run_importmap_command_expecting_failure("update", "md5", "nope")

    assert_includes out, %(Couldn't find a pin for "nope")
    assert_not_includes out, "Pinning"
    assert_includes File.read("#{@tmpdir}/dummy/config/importmap.rb"), "md5@2.2.0"
  end

  test "update command reports named packages that are up to date or have no version" do
    importmap_config(<<~PINS)
      pin "md5", to: "https://cdn.jsdelivr.net/npm/md5@2.3.0/md5.js"
      pin "application"
    PINS

    out, _err = run_importmap_command("update", "md5", "application")

    assert_includes out, %("md5" is already up to date (2.3.0))
    assert_includes out, %(Can't tell whether "application" is outdated: its pin has no version)
    assert_includes out, "No outdated packages found"
  end

  test "update command with a subpath name re-pins that key" do
    importmap_config('pin "photoswipe/lightbox", to: "https://ga.jspm.io/npm:photoswipe@5.3.0/dist/photoswipe-lightbox.esm.js"')

    out, _err = run_importmap_command("update", "photoswipe/lightbox")

    assert_includes out, 'Pinning "photoswipe/lightbox"'

    content = File.read("#{@tmpdir}/dummy/config/importmap.rb")
    assert_match %r{^pin "photoswipe/lightbox", to: "https://ga.jspm.io/npm:photoswipe@5\.4\.\d+/dist/photoswipe-lightbox\.esm\.js"$}, content
    assert_not_includes content, "photoswipe@5.3.0"
  end

  test "update command with no names re-pins the subpath key, not the package name" do
    importmap_config('pin "photoswipe/lightbox", to: "https://ga.jspm.io/npm:photoswipe@5.3.0/dist/photoswipe-lightbox.esm.js"')

    out, _err = run_importmap_command("update")

    assert_includes out, 'Pinning "photoswipe/lightbox"'

    content = File.read("#{@tmpdir}/dummy/config/importmap.rb")
    assert_match %r{^pin "photoswipe/lightbox", to: "https://ga.jspm.io/npm:photoswipe@5\.4\.\d+/dist/photoswipe-lightbox\.esm\.js"$}, content
    assert_not_includes content, "photoswipe@5.3.0"
    assert_no_match %r{^pin "photoswipe"}, content
  end

  test "update command with --all re-pins every key carrying an outdated package" do
    importmap_config(<<~PINS)
      pin "photoswipe", to: "https://ga.jspm.io/npm:photoswipe@5.3.0/dist/photoswipe.esm.js"
      pin "photoswipe/lightbox", to: "https://ga.jspm.io/npm:photoswipe@5.3.0/dist/photoswipe-lightbox.esm.js"
    PINS

    out, _err = run_importmap_command("update", "--all")

    assert_includes out, 'Pinning "photoswipe"'
    assert_includes out, 'Pinning "photoswipe/lightbox"'

    content = File.read("#{@tmpdir}/dummy/config/importmap.rb")
    assert_match %r{^pin "photoswipe", to: "https://ga.jspm.io/npm:photoswipe@5\.4\.\d+/dist/photoswipe\.esm\.js"$}, content
    assert_match %r{^pin "photoswipe/lightbox", to: "https://ga.jspm.io/npm:photoswipe@5\.4\.\d+/dist/photoswipe-lightbox\.esm\.js"$}, content
    assert_not_includes content, "photoswipe@5.3.0"
    assert_equal 2, content.lines.count { |line| line.start_with?("pin ") }
  end

  test "update command leaves a local pin that shares a namespace with an outdated package" do
    importmap_config(<<~PINS)
      pin "md5", to: "https://cdn.jsdelivr.net/npm/md5@2.2.0/md5.js"
      pin "md5/helpers", to: "md5/helpers.js"
    PINS

    out, _err = run_importmap_command("update")

    assert_includes out, 'Pinning "md5"'

    content = File.read("#{@tmpdir}/dummy/config/importmap.rb")
    assert_includes content, "md5@2.3.0"
    assert_includes content, %(pin "md5/helpers", to: "md5/helpers.js")
  end

  test "update command re-resolves a remote subpath pin from the CDN it is on" do
    importmap_config('pin "photoswipe/lightbox", to: "https://cdn.jsdelivr.net/npm/photoswipe@5.3.0/dist/photoswipe-lightbox.esm.js"')

    out, _err = run_importmap_command("update")

    assert_includes out, 'Pinning "photoswipe/lightbox"'

    content = File.read("#{@tmpdir}/dummy/config/importmap.rb")
    assert_match %r{^pin "photoswipe/lightbox", to: "https://cdn\.jsdelivr\.net/npm/photoswipe@5\.4\.\d+/dist/photoswipe-lightbox\.esm\.js"$}, content
  end

  test "update command reports a name whose package is pinned under another key" do
    importmap_config('pin "photoswipe/lightbox", to: "https://ga.jspm.io/npm:photoswipe@5.3.0/dist/photoswipe-lightbox.esm.js"')

    out, _err = run_importmap_command_expecting_failure("update", "photoswipe")

    assert_includes out, %(Couldn't find a pin for "photoswipe")
    assert_includes File.read("#{@tmpdir}/dummy/config/importmap.rb"), "photoswipe@5.3.0"
  end

  test "outdated command shows locked packages and exits 0 when nothing unlocked is outdated" do
    importmap_config('pin "md5", to: "https://cdn.jsdelivr.net/npm/md5@2.2.0/md5.js", preload: true # @2.2.0 (locked)')

    out, _err = run_importmap_command("outdated")

    assert_match(/\| md5\s+\| 2\.2\.0\s+\| \S+\s+\| yes\s+\|/, out)
    assert_includes out, "1 outdated package found (1 locked)"
  end

  test "outdated command exits 1 when an unlocked package is outdated" do
    FileUtils.cp("#{__dir__}/fixtures/files/outdated_import_map.rb", "#{@tmpdir}/dummy/config/importmap.rb")

    out, _err = run_importmap_command_expecting_failure("outdated")

    assert_includes out, "1 outdated package found\n"
  end

  test "pristine command redownloads a locked package and keeps the lock" do
    importmap_config("")
    run_importmap_command("pin", "md5@2.2.0", "--lock")

    original = File.read("#{@tmpdir}/dummy/vendor/javascript/md5.js")
    File.write("#{@tmpdir}/dummy/vendor/javascript/md5.js", "corrupted")

    out, _err = run_importmap_command("pristine")

    assert_includes out, 'Downloading "md5"'
    assert_equal original, File.read("#{@tmpdir}/dummy/vendor/javascript/md5.js")
    assert_includes File.read("#{@tmpdir}/dummy/config/importmap.rb"), %(pin "md5" # @2.2.0 (locked)\n)

    run_importmap_command("pristine", "--from", "esm.run")

    assert_includes File.read("#{@tmpdir}/dummy/config/importmap.rb"), %(pin "md5" # @2.2.0 (esm.run, locked)\n)
  end

  test "update command leaves a package alone when the registry couldn't be checked" do
    importmap_config('pin "md5", to: "https://cdn.jsdelivr.net/npm/md5@2.2.0/md5.js"')
    stub_registry_failures("md5" => "Unexpected error response 500: Service unavailable")

    out, _err = run_importmap_command_expecting_failure("update")

    assert_includes out, %(Couldn't check "md5": Unexpected error response 500: Service unavailable)
    assert_not_includes out, "Pinning"
    assert_not_includes out, "No outdated packages found"
    assert_includes File.read("#{@tmpdir}/dummy/config/importmap.rb"), "md5@2.2.0"
  end

  test "update command updates the rest when a named package couldn't be checked" do
    importmap_config(<<~PINS)
      pin "md5", to: "https://cdn.jsdelivr.net/npm/md5@2.2.0/md5.js"
      pin "luxon", to: "https://cdn.jsdelivr.net/npm/luxon@3.0.0/build/es6/luxon.mjs"
    PINS
    stub_registry_failures("md5" => "Unexpected error response 404: Not found")

    out, _err = run_importmap_command_expecting_failure("update", "md5", "luxon")

    assert_includes out, %(Couldn't check "md5": Unexpected error response 404: Not found)
    assert_not_includes out, "is already up to date"
    assert_not_includes out, 'Pinning "md5"'
    assert_includes out, 'Pinning "luxon"'

    content = File.read("#{@tmpdir}/dummy/config/importmap.rb")
    assert_includes content, "md5@2.2.0"
    assert_match %r{^pin "luxon", to: "https://cdn.jsdelivr.net/npm/luxon@3\.\d+\.\d+/build/es6/luxon\.mjs"$}, content
    assert_not_includes content, "luxon@3.0.0"
  end

  test "outdated command reports a package the registry couldn't answer for" do
    importmap_config(<<~PINS)
      pin "md5", to: "https://cdn.jsdelivr.net/npm/md5@2.2.0/md5.js"
      pin "luxon", to: "https://cdn.jsdelivr.net/npm/luxon@3.0.0/build/es6/luxon.mjs"
    PINS
    stub_registry_failures("md5" => "Unexpected error response 500: Service unavailable")

    out, _err = run_importmap_command_expecting_failure("outdated")

    assert_match(/\| md5\s+\| 2\.2\.0\s+\| Unexpected error response 500: Service unavailable\s+\|/, out)
    assert_match(/\| luxon\s+\| 3\.0\.0\s+\| 3\.\d+\.\d+\s+\|/, out)
    assert_includes out, "2 outdated packages found"
  end

  test "pin command keeps a package remote when its file can't stand alone, and says why" do
    importmap_config("")

    out, _err = run_importmap_command("pin", "@popperjs/core@2.11.8")

    assert_includes out, 'Pinning "@popperjs/core" to https://ga.jspm.io/npm:@popperjs/core@2.11.8/lib/index.js (kept remote: relative imports)'
    assert_not_includes out, "via download"

    content = File.read("#{@tmpdir}/dummy/config/importmap.rb")
    assert_includes content, %(pin "@popperjs/core", to: "https://ga.jspm.io/npm:@popperjs/core@2.11.8/lib/index.js" # @2.11.8 (remote: relative imports)\n)
    assert_not File.exist?("#{@tmpdir}/dummy/vendor/javascript/@popperjs--core.js")
  end

  test "pin command with --vendor downloads a package that can't stand alone anyway" do
    importmap_config("")

    out, _err = run_importmap_command("pin", "@popperjs/core@2.11.8", "--vendor")

    assert_includes out, 'Pinning "@popperjs/core" to vendor/javascript/@popperjs/core.js via download'
    assert_not_includes out, "kept remote"

    content = File.read("#{@tmpdir}/dummy/config/importmap.rb")
    assert_includes content, %(pin "@popperjs/core", to: "@popperjs--core.js" # @2.11.8 (vendored)\n)
    assert File.exist?("#{@tmpdir}/dummy/vendor/javascript/@popperjs--core.js")
  end

  test "pin command with --vendor converts a pin that was kept remote back to a download" do
    importmap_config('pin "@popperjs/core", to: "https://ga.jspm.io/npm:@popperjs/core@2.11.8/lib/index.js" # @2.11.8 (remote: relative imports)')

    run_importmap_command("pin", "@popperjs/core@2.11.8", "--vendor")

    content = File.read("#{@tmpdir}/dummy/config/importmap.rb")
    assert_includes content, %(pin "@popperjs/core", to: "@popperjs--core.js" # @2.11.8 (vendored)\n)
    assert_not_includes content, "remote:"
    assert File.exist?("#{@tmpdir}/dummy/vendor/javascript/@popperjs--core.js")
  end

  test "update command leaves a pin that was kept remote remote, with its reason" do
    importmap_config('pin "@popperjs/core", to: "https://ga.jspm.io/npm:@popperjs/core@2.11.7/lib/index.js" # @2.11.7 (remote: relative imports)')

    out, _err = run_importmap_command("update")

    assert_includes out, 'Pinning "@popperjs/core"'

    content = File.read("#{@tmpdir}/dummy/config/importmap.rb")
    assert_match %r{^pin "@popperjs/core", to: "https://ga\.jspm\.io/npm:@popperjs/core@2\.11\.\d+/lib/index\.js" # @2\.11\.\d+ \(remote: relative imports\)$}, content
    assert_not File.exist?("#{@tmpdir}/dummy/vendor/javascript/@popperjs--core.js")
  end

  test "update command keeps a package vendored with --vendor vendored" do
    importmap_config("")

    run_importmap_command("pin", "@popperjs/core@2.11.7", "--vendor")

    out, _err = run_importmap_command("update")

    assert_includes out, 'Pinning "@popperjs/core"'

    content = File.read("#{@tmpdir}/dummy/config/importmap.rb")
    assert_match %r{^pin "@popperjs/core", to: "@popperjs--core\.js" # @2\.11\.\d+ \(vendored\)$}, content
    assert File.exist?("#{@tmpdir}/dummy/vendor/javascript/@popperjs--core.js")
  end

  test "pin command with --lock locks a package it kept remote" do
    importmap_config("")

    out, _err = run_importmap_command("pin", "@popperjs/core@2.11.8", "--lock")

    assert_includes out, "kept remote: relative imports"
    assert_includes out, 'Locked "@popperjs/core" at 2.11.8'

    content = File.read("#{@tmpdir}/dummy/config/importmap.rb")
    assert_includes content, %(# @2.11.8 (remote: relative imports, locked)\n)
  end

  test "pin command keeps the options of a pin it keeps remote" do
    importmap_config('pin "@popperjs/core", to: "@popperjs--core.js", preload: false # @2.11.7')

    run_importmap_command("pin", "@popperjs/core@2.11.8")

    content = File.read("#{@tmpdir}/dummy/config/importmap.rb")
    assert_includes content, %(pin "@popperjs/core", to: "https://ga.jspm.io/npm:@popperjs/core@2.11.8/lib/index.js", preload: false # @2.11.8 (remote: relative imports)\n)
  end

  test "update command with a package name re-pins every key of that package" do
    importmap_config(<<~PINS)
      pin "photoswipe" # @5.3.0 (jsdelivr)
      pin "photoswipe/lightbox", to: "photoswipe--lightbox.js" # @5.3.0 (jsdelivr)
    PINS

    out, _err = run_importmap_command("update", "photoswipe")

    assert_includes out, 'Pinning "photoswipe" to vendor/javascript/photoswipe.js via download from https://cdn.jsdelivr.net/npm/photoswipe@5.4.'
    assert_includes out, 'Pinning "photoswipe/lightbox" to vendor/javascript/photoswipe/lightbox.js via download from https://cdn.jsdelivr.net/npm/photoswipe@5.4.'

    content = File.read("#{@tmpdir}/dummy/config/importmap.rb")
    assert_match %r{^pin "photoswipe" # @5\.4\.\d+ \(jsdelivr\)$}, content
    assert_match %r{^pin "photoswipe/lightbox", to: "photoswipe--lightbox\.js" # @5\.4\.\d+ \(jsdelivr\)$}, content
    assert_not_includes content, "@5.3.0"
    assert File.exist?("#{@tmpdir}/dummy/vendor/javascript/photoswipe--lightbox.js")
  end

  test "update command resolves a subpath pin from the CDN its package's remote pin points at" do
    importmap_config(<<~PINS)
      pin "photoswipe", to: "https://cdn.jsdelivr.net/npm/photoswipe@5.3.0/dist/photoswipe.esm.js"
      pin "photoswipe/lightbox", to: "photoswipe--lightbox.js" # @5.3.0
    PINS

    out, _err = run_importmap_command("update")

    assert_not_includes out, "ga.jspm.io"
    assert_not_includes out, "Couldn't find any packages"

    content = File.read("#{@tmpdir}/dummy/config/importmap.rb")
    assert_match %r{^pin "photoswipe/lightbox", to: "photoswipe--lightbox\.js" # @5\.4\.\d+ \(jsdelivr\)$}, content
  end

  test "update command resolves a subpath pin from its own CDN, not its package's" do
    importmap_config(<<~PINS)
      pin "photoswipe" # @5.3.0 (skypack)
      pin "photoswipe/lightbox", to: "https://cdn.jsdelivr.net/npm/photoswipe@5.3.0/dist/photoswipe-lightbox.esm.js"
    PINS

    out, _err = run_importmap_command("update")

    # The remote pin says jsdelivr, so the subpath is asked of jsdelivr. Taking
    # the package's skypack instead grouped the two into one request, and one
    # spec skypack can't answer for fails the whole batch, subpath included.
    content = File.read("#{@tmpdir}/dummy/config/importmap.rb")
    assert_match %r{^pin "photoswipe/lightbox", to: "https://cdn\.jsdelivr\.net/npm/photoswipe@5\.4\.\d+/dist/photoswipe-lightbox\.esm\.js"$}, content

    # Both sides are asserted so neither can fail quietly. skypack stopped
    # publishing years ago and has no photoswipe 5.4, so the package's own pin
    # can't move — but it now fails alone rather than taking the subpath down
    # with it, which is the whole point: the batch names one spec, not two.
    assert_includes out, %(Couldn't find any packages in ["photoswipe"] on skypack)
    assert_includes content, %(pin "photoswipe" # @5.3.0 (skypack)\n)
  end

  test "update command with a subpath name re-pins only that key" do
    importmap_config(<<~PINS)
      pin "photoswipe" # @5.3.0 (jsdelivr)
      pin "photoswipe/lightbox", to: "photoswipe--lightbox.js" # @5.3.0 (jsdelivr)
    PINS

    out, _err = run_importmap_command("update", "photoswipe/lightbox")

    assert_includes out, 'Pinning "photoswipe/lightbox"'
    assert_not_includes out, 'Pinning "photoswipe" '

    content = File.read("#{@tmpdir}/dummy/config/importmap.rb")
    assert_includes content, %(pin "photoswipe" # @5.3.0 (jsdelivr)\n)
    assert_match %r{^pin "photoswipe/lightbox", to: "photoswipe--lightbox\.js" # @5\.4\.\d+ \(jsdelivr\)$}, content
  end

  test "update command resolves a subpath pin from the CDN its package's pin names" do
    importmap_config(<<~PINS)
      pin "photoswipe" # @5.3.0 (jsdelivr)
      pin "photoswipe/lightbox", to: "photoswipe--lightbox.js" # @5.3.0
    PINS

    out, _err = run_importmap_command("update")

    assert_includes out, 'Pinning "photoswipe/lightbox" to vendor/javascript/photoswipe/lightbox.js via download from https://cdn.jsdelivr.net/npm/photoswipe@5.4.'
    assert_not_includes out, "ga.jspm.io"

    content = File.read("#{@tmpdir}/dummy/config/importmap.rb")
    assert_match %r{^pin "photoswipe/lightbox", to: "photoswipe--lightbox\.js" # @5\.4\.\d+ \(jsdelivr\)$}, content
  end

  # jspm's generator can't build mermaid — it reads cytoscape's package.json and
  # finds no export for the subpath mermaid imports. jsDelivr publishes a bundle
  # of the same version, so the package is fine and the generator isn't.
  test "pin falls back to the next CDN when jspm can't resolve a package" do
    importmap_config("")

    out, _err = run_importmap_command("pin", "mermaid@10.6.0")

    assert_match %r{jspm couldn't resolve "mermaid@10\.6\.0" \(.*cytoscape.*\); trying esm\.run}, out
    assert_includes out, 'Pinning "mermaid" to vendor/javascript/mermaid.js via download from https://cdn.jsdelivr.net/npm/mermaid@10.6.0/+esm'

    assert_includes File.read("#{@tmpdir}/dummy/config/importmap.rb"), %(pin "mermaid" # @10.6.0 (esm.run)\n)
    assert File.exist?("#{@tmpdir}/dummy/vendor/javascript/mermaid.js")
  end

  # --from is a choice somebody made, so it is asked once and reported on.
  test "pin asks only the CDN it was told to and says why that one couldn't" do
    importmap_config("")

    out, _err = run_importmap_command("pin", "mermaid@10.6.0", "--from", "jspm")

    assert_not_includes out, "trying esm.run"
    assert_includes out, %(Couldn't find any packages in ["mermaid@10.6.0"] on jspm)
    assert_match(/cytoscape/, out)

    assert_not_includes File.read("#{@tmpdir}/dummy/config/importmap.rb"), "mermaid"
  end

  test "pin resolves a package with no version from the npm registry" do
    importmap_config("")

    out, _err = run_importmap_command("pin", "md5")

    version = out[/Resolved "md5" to (\d+\.\d+\.\d+) from the npm registry/, 1]
    assert version, "expected the registry version to be reported, got:\n#{out}"

    assert_includes out, "https://ga.jspm.io/npm:md5@#{version}/md5.js"
    assert_includes File.read("#{@tmpdir}/dummy/config/importmap.rb"), %(pin "md5" # @#{version}\n)
  end

  test "pin leaves a version it was given alone" do
    importmap_config("")

    out, _err = run_importmap_command("pin", "md5@2.2.0")

    assert_not_includes out, "from the npm registry"
    assert_includes File.read("#{@tmpdir}/dummy/config/importmap.rb"), %(pin "md5" # @2.2.0\n)
  end

  # jsDelivr serves the package's own dist file, which for google-libphonenumber
  # is the UMD bundle it has always shipped: vendoring it gives an import map
  # entry that exports nothing.
  test "pin keeps a package remote when the CDN hands back something that isn't an ES module" do
    importmap_config("")

    out, _err = run_importmap_command("pin", "google-libphonenumber@3.2.42", "--from", "jsdelivr")

    assert_includes out, 'Pinning "google-libphonenumber" to https://cdn.jsdelivr.net/npm/google-libphonenumber@3.2.42/dist/libphonenumber.js (kept remote: not an ES module)'

    content = File.read("#{@tmpdir}/dummy/config/importmap.rb")
    assert_includes content, %(# @3.2.42 (remote: not an ES module))
    assert_not File.exist?("#{@tmpdir}/dummy/vendor/javascript/google-libphonenumber.js")
  end

  test "pin vendors something that isn't an ES module when told to" do
    importmap_config("")

    out, _err = run_importmap_command("pin", "google-libphonenumber@3.2.42", "--from", "jsdelivr", "--vendor")

    assert_includes out, 'Pinning "google-libphonenumber" to vendor/javascript/google-libphonenumber.js via download'
    assert File.exist?("#{@tmpdir}/dummy/vendor/javascript/google-libphonenumber.js")
  end

  # A pin with no CDN in its comment is a jspm pin, and jspm can't build the
  # version this one is moving to either. The pin that comes out names esm.run,
  # so the next command goes straight there.
  test "update falls back for a pin whose CDN can't build the new version" do
    importmap_config(%(pin "mermaid" # @10.6.0))

    out, _err = run_importmap_command("update")

    # update names the pin's key, not a spec: the version it moves to is the
    # CDN's to resolve, the same way a bare update has always worked.
    assert_match(/jspm couldn't resolve "mermaid" \(.+\); trying esm\.run/, out)
    assert_match %r{^pin "mermaid" # @1[12]\.\d+\.\d+ \(esm\.run\)$}, File.read("#{@tmpdir}/dummy/config/importmap.rb")
  end

  # pristine restores what a pin already says. Moving a package to another CDN
  # would be a rewrite, so the CDN the pin names is asked, and only that one.
  test "pristine asks the CDN the pin names and doesn't fall back" do
    importmap_config(%(pin "mermaid" # @10.6.0))

    out, _err = run_importmap_command("pristine")

    assert_not_includes out, "trying esm.run"
    assert_includes out, %(Couldn't find any packages in ["mermaid@10.6.0"] on jspm)
    assert_match(/cytoscape/, out)
    assert_includes File.read("#{@tmpdir}/dummy/config/importmap.rb"), %(pin "mermaid" # @10.6.0\n)
  end

  private
    # A registry that can't answer for a package is the case under test, and
    # the live registry won't produce it on demand. Stub the one method that
    # talks to it, per package by URI path, so get_package's own error
    # handling and every layer above it — outdated_packages, outdated,
    # update, the pin rewriting — still run for real. Packages not named
    # here go to the live registry, which is what the mixed cases rely on.
    def stub_registry_failures(failures)
      path = "#{@tmpdir}/dummy/bin/importmap"

      File.write(path, <<~RUBY)
        #!/usr/bin/env ruby

        require_relative "../config/application"
        require "importmap/npm"

        REGISTRY_FAILURES = #{failures.inspect}

        Importmap::Npm.prepend(Module.new do
          private def get_json(uri)
            message = REGISTRY_FAILURES[uri.path.delete_prefix("/")]
            message ? raise(Importmap::Npm::HTTPError, message) : super
          end
        end)

        require "importmap/commands"
      RUBY
      FileUtils.chmod(0755, path)
    end

    def run_importmap_command_expecting_failure(command, *args)
      status = nil
      out, err = capture_subprocess_io { status = system("bin/importmap", command, *args) }

      flunk "bin/importmap #{[command, *args].join(" ")} succeeded, expected a failure:\n#{out}#{err}" if status

      [out, err]
    end

    def minifier_available?
      require "importmap/minifier"
      Importmap::Minifier.available?
    end

    def importmap_config(content)
      File.write("#{@tmpdir}/dummy/config/importmap.rb", "#{content}\n")
    end

    # bin/importmap talks to live CDNs, so when it fails the reason is in its
    # output — surface it instead of a bare "Command failed with exit 1".
    def run_importmap_command(command, *args)
      status = nil
      out, err = capture_subprocess_io { status = system("bin/importmap", command, *args) }

      flunk "bin/importmap #{[command, *args].join(" ")} failed (#{$?.exitstatus.inspect}):\n#{out}#{err}" unless status

      [out, err]
    end
end
