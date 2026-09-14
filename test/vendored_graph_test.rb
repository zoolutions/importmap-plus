require "test_helper"
require "importmap/vendored_graph"
require "importmap/package_graph"
require "importmap/packager"

class Importmap::VendoredGraphTest < ActiveSupport::TestCase
  test "the line it renders carries the directory, the package and the version" do
    assert_equal %(pin_all_from "vendor/javascript/pkg", under: "pkg" # @1.0.0 (graph of pkg)),
      vendored_graph("vendor/javascript/pkg").line_for(under: "pkg", version: "@1.0.0")
    assert_equal %(pin_all_from "vendor/javascript/@popperjs--core", under: "@popperjs/core", to: "@popperjs--core" # @2.11.8 (graph of @popperjs/core)),
      vendored_graph("vendor/javascript/@popperjs--core").line_for(under: "@popperjs/core", version: "2.11.8")
    assert_equal %(pin_all_from "vendor/javascript/buffer", under: "@jspm/core", to: "buffer", preload: false # @2.1.0 (graph of @jspm/core)),
      vendored_graph("vendor/javascript/buffer").line_for(under: "@jspm/core", version: "@2.1.0", options: ", preload: false")
  end

  test "a line is found by its own directory and by no other" do
    line = vendored_graph("vendor/javascript/pkg").line_for(under: "pkg", version: "@1.0.0")

    assert_match Importmap::VendoredGraph.line_regexp_for("vendor/javascript/pkg"), line
    assert_no_match Importmap::VendoredGraph.line_regexp_for("vendor/javascript/pkg--sub"), line
    assert_no_match Importmap::VendoredGraph.line_regexp_for("vendor/javascript/p"), line
    assert_no_match Importmap::VendoredGraph.line_regexp_for("vendor/javascript/pkg"), %(# #{line})
    assert_no_match Importmap::VendoredGraph.line_regexp_for("vendor/javascript/pkg"), %(pin "a"; #{line})
    # A pin_all_from an app wrote itself carries no comment, so it is neither
    # rewritten nor taken for a directory this gem may delete.
    assert_no_match Importmap::VendoredGraph.line_regexp_for("vendor/javascript/pkg"),
      %(pin_all_from "vendor/javascript/pkg", under: "pkg")
    # The accepted limit, asserted so a change to the anchor is noticed: a
    # second statement after the line is swallowed with it, exactly as it is by
    # upstream's own Map.pin_line_regexp_for.
    assert_match Importmap::VendoredGraph.line_regexp_for("vendor/javascript/pkg"),
      %(pin_all_from "vendor/javascript/pkg", under: "pkg"; pin "evil" # @1.0.0 (graph of pkg))
  end

  # A pin_all_from line must be invisible to every regex that reads pins, or
  # update, outdated, lock and unpin would take it for one.
  test "the line it renders is invisible to the pin regexes" do
    line = vendored_graph("vendor/javascript/@popperjs--core").line_for(under: "@popperjs/core", version: "@2.11.8")

    assert_no_match Importmap::Map::PIN_REGEX, line
    assert_no_match Importmap::Map.pin_line_regexp_for("@popperjs/core"), line
    assert_no_match Importmap::Packager::PIN_REGEX, line
    assert_empty line.scan(/^pin .*(?<=npm:|npm\/)([^@\/]+)@(\d+\.\d+\.\d+)/)
  end

  test "mapping_for names the package whose directory already maps a key" do
    Dir.mktmpdir do |dir|
      FileUtils.mkdir_p("#{dir}/date-fns/format")
      File.write("#{dir}/date-fns/format/index.js", "export default 1")
      File.write("#{dir}/date-fns/add.js", "export default 1")
      importmap = %(pin_all_from "#{dir}/date-fns", under: "date-fns" # @2.30.0 (graph of date-fns)\n)

      assert_equal "date-fns", Importmap::VendoredGraph.mapping_for(importmap, "date-fns/format")
      assert_equal "date-fns", Importmap::VendoredGraph.mapping_for(importmap, "date-fns/add")
      assert_nil Importmap::VendoredGraph.mapping_for(importmap, "date-fns/missing")
      assert_nil Importmap::VendoredGraph.mapping_for(importmap, "luxon")
    end
  end

  test "conflict_in finds another directory mapping the same package at another version" do
    importmap = %(pin_all_from "vendor/javascript/buffer", under: "@jspm/core" # @2.1.0 (graph of @jspm/core)\n)

    assert_equal [ "vendor/javascript/buffer", "@jspm/core", "2.1.0" ],
      Importmap::VendoredGraph.conflict_in(importmap, under: "@jspm/core", version: "@2.0.0", except: "vendor/javascript/crypto")
    assert_nil Importmap::VendoredGraph.conflict_in(importmap, under: "@jspm/core", version: "2.1.0", except: "vendor/javascript/crypto")
    assert_nil Importmap::VendoredGraph.conflict_in(importmap, under: "@jspm/core", version: "@2.0.0", except: "vendor/javascript/buffer")
  end

  test "entry_urls reads the CDN URL out of each vendored file's header" do
    Dir.mktmpdir do |dir|
      File.write("#{dir}/md5.js", "// md5@2.2.0 downloaded from https://ga.jspm.io/npm:md5@2.2.0/md5.js\n\nexport default 1")
      File.write("#{dir}/luxon.js", "// luxon@3.7.2 downloaded from https://cdn.jsdelivr.net/npm/luxon@3.7.2/x.js (minified)\nx")
      File.write("#{dir}/app.js", "export default 1")
      # A file the gem didn't write can hold bytes no UTF-8 regexp can read
      # without raising, and must not stop the others from being read.
      File.binwrite("#{dir}/binary.js", "\x1b!\x06\x00\x8c\xd3".dup.force_encoding("ASCII-8BIT"))

      urls = Importmap::VendoredGraph.entry_urls(
        %w[ md5 luxon app binary missing ].to_h { |key| [ key, Pathname.new(dir).join("#{key}.js") ] })

      assert_equal({ "https://ga.jspm.io/npm:md5@2.2.0/md5.js" => "md5",
                     "https://cdn.jsdelivr.net/npm/luxon@3.7.2/x.js" => "luxon" }, urls)
    end
  end

  test "commit puts the directory the app has back when the swap fails" do
    Dir.mktmpdir do |dir|
      target = Pathname.new(dir).join("pkg")
      FileUtils.mkdir_p target
      File.write(target.join("works.js"), "// the files that work today")
      importmap = File.join(dir, "importmap.rb")
      File.write(importmap, %(pin_all_from "#{target}", under: "pkg" # @1.0.0 (graph of pkg)\n))

      graph = vendored_graph(target, importmap)
      partial = graph.write(Struct.new(:files).new({ "new.js" => "export default 1" }))
      FileUtils.rm_rf partial

      assert_raises(Errno::ENOENT) { graph.commit(partial) }

      assert_equal "// the files that work today", File.read(target.join("works.js"))
      assert_empty Dir.glob("#{dir}/*.previous")
    end
  end

  # Between renaming the app's directory aside and renaming the new one in,
  # the app has neither. Ctrl-C there is not a StandardError, and a rescue
  # that put the old one back would not run for it.
  test "commit puts the directory the app has back when the swap is interrupted" do
    Dir.mktmpdir do |dir|
      target = Pathname.new(dir).join("pkg")
      FileUtils.mkdir_p target
      File.write(target.join("works.js"), "// the files that work today")
      importmap = File.join(dir, "importmap.rb")
      File.write(importmap, %(pin_all_from "#{target}", under: "pkg" # @1.0.0 (graph of pkg)\n))

      graph = vendored_graph(target, importmap)
      partial = graph.write(Struct.new(:files).new({ "new.js" => "export default 1" }))
      rename = File.method(:rename)

      File.stub(:rename, ->(from, to) { from.to_s == partial.to_s ? raise(Interrupt) : rename.call(from, to) }) do
        assert_raises(Interrupt) { graph.commit(partial) }
      end

      assert_equal "// the files that work today", File.read(target.join("works.js"))
      assert_empty Dir.glob("#{dir}/*.previous")
    end
  end

  test "commit refuses to replace a directory the import map doesn't map as ours" do
    Dir.mktmpdir do |dir|
      target = Pathname.new(dir).join("pkg")
      FileUtils.mkdir_p target
      File.write(target.join("theirs.js"), "// the app's own")
      importmap = File.join(dir, "importmap.rb")
      File.write(importmap, %(pin_all_from "#{target}", under: "pkg"\n))

      graph = vendored_graph(target, importmap)
      partial = graph.write(Struct.new(:files).new({ "new.js" => "export default 1" }))

      assert_raises(Importmap::VendoredGraph::Occupied) { graph.commit(partial) }

      assert_equal "// the app's own", File.read(target.join("theirs.js"))
    end
  end

  # Ctrl-C during a 250-file minify is the likeliest way this ends early, and
  # Interrupt is not a StandardError — a bare rescue would leave the directory
  # behind under a pid no later run will match.
  test "write cleans up its own partial however the write ends" do
    [ RuntimeError, Interrupt ].each do |giving_up|
      Dir.mktmpdir do |dir|
        graph = vendored_graph(Pathname.new(dir).join("pkg"))

        assert_raises(giving_up) do
          graph.write(Struct.new(:files).new({ "a.js" => "1", "b.js" => "2" })) do |source|
            raise giving_up, "the minifier gave up" if source == "2"

            source
          end
        end

        assert_empty Dir.glob("#{dir}/*.download"), "expected no partial after #{giving_up}"
      end
    end
  end

  private
    def vendored_graph(directory, importmap = "config/importmap.rb")
      Importmap::VendoredGraph.new(directory, importmap_path: importmap)
    end
end
