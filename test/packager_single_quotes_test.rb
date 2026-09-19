require "test_helper"
require "importmap/packager"

class Importmap::PackagerSingleQuotesTest < ActiveSupport::TestCase
  setup do
    @single_quote_config_name = Rails.root.join("config/importmap_with_single_quotes.rb")
    File.write(@single_quote_config_name, File.read(Rails.root.join("config/importmap.rb")).tr('"', "'"))
    @packager = Importmap::Packager.new(@single_quote_config_name)
  end

  teardown { File.delete(@single_quote_config_name) }

  test "packaged? with single quotes" do
    assert @packager.packaged?("md5")
    assert_not @packager.packaged?("md5-extension")
  end

  test "remove package with single quotes" do
    assert @packager.remove("md5")
    assert_not @packager.packaged?("md5")
  end

  test "extract_existing_pin_options with single quotes" do
    assert_equal({ preload: true, to: "https://cdn.skypack.dev/md5", integrity: false },
                 @packager.extract_existing_pin_options("md5")["md5"])
  end

  test "an array preload with single quotes is read and written back without its quotes mattering" do
    packager = Importmap::Packager.new(file_fixture("single_quote_array_preload_import_map.rb"))

    assert_equal [ "admin", "app" ], packager.extract_existing_pin_options("charenc")["charenc"][:preload]
    assert_equal %(pin "charenc", preload: ["admin", "app"]),
                 packager.pin_for("charenc", preloads: [ "admin", "app" ])
    assert_equal %(pin "crypt", preload: []), packager.pin_for("crypt", preloads: [])
  end
end
