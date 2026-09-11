require "test_helper"
require "importmap/minifier"

class Importmap::MinifierTest < ActiveSupport::TestCase
  test "raises a helpful error when no minifier is installed" do
    error = assert_raises(Importmap::Minifier::Error) { Importmap::Minifier.new(nil).call("const a = 1") }

    assert_match(/install bun, esbuild or terser/, error.message)
  end

  test "accepts a tool name as a symbol" do
    assert_equal "esbuild", Importmap::Minifier.new(:esbuild).tool
    assert_equal "terser", Importmap::Minifier.new("terser").tool
    assert_nil Importmap::Minifier.new(nil).tool
  end

  test "finds a tool in node_modules/.bin before looking on PATH" do
    Dir.mktmpdir do |dir|
      Dir.chdir(dir) do
        FileUtils.mkdir_p("node_modules/.bin")
        File.write("node_modules/.bin/importmap-fake-minifier", "#!/bin/sh\n")
        File.chmod(0755, "node_modules/.bin/importmap-fake-minifier")

        assert_equal File.expand_path("node_modules/.bin/importmap-fake-minifier"),
                     Importmap::Minifier.executable_for("importmap-fake-minifier")
        assert_nil Importmap::Minifier.executable_for("importmap-missing-minifier")
      end
    end
  end

  test "finds a Windows .cmd shim, which is how npm installs these tools there" do
    Dir.mktmpdir do |dir|
      Dir.chdir(dir) do
        FileUtils.mkdir_p("node_modules/.bin")
        File.write("node_modules/.bin/importmap-fake-minifier.CMD", "@echo off\n")
        File.chmod(0755, "node_modules/.bin/importmap-fake-minifier.CMD")

        # Windows finds it without the stub, which is the point of the stub.
        assert_nil Importmap::Minifier.executable_for("importmap-fake-minifier") unless Gem.win_platform?

        Gem.stub(:win_platform?, true) do
          assert_equal File.expand_path("node_modules/.bin/importmap-fake-minifier.CMD"),
                       Importmap::Minifier.executable_for("importmap-fake-minifier")
        end
      end
    end
  end

  test "minifies with the detected tool and keeps bare import specifiers intact" do
    skip "no JavaScript minifier installed (bun, esbuild or terser)" unless Importmap::Minifier.available?

    source = <<~JS
      import { Controller } from "@hotwired/stimulus"

      export default class extends Controller {
        connect() {
          // a comment the minifier should drop
          this.element.textContent = "hello   world"
        }
      }
    JS

    minified = Importmap::Minifier.new.call(source)

    assert_operator minified.bytesize, :<, source.bytesize
    assert_includes minified, %("@hotwired/stimulus")
    assert_includes minified, "hello   world"
    assert_not_includes minified, "a comment the minifier should drop"
  end
end
