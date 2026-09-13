require "test_helper"
require "importmap/integrity"

class Importmap::IntegrityTest < ActiveSupport::TestCase
  # Computed with: printf 'export default 1' | openssl dgst -sha384 -binary | base64
  KNOWN_SHA384 = "sha384-0DeSvYsDquR15dA3vw6sdT+tE32nJCBO6Aklkh06a82PqZy0X9FKOJD+lF0u7oz4"

  test "for hashes a body the way a browser will" do
    assert_equal KNOWN_SHA384, Importmap::Integrity.for("export default 1")
  end

  test "for hashes bytes, not characters" do
    body = "export default \"café\"".dup.force_encoding(Encoding::BINARY)

    assert_equal Importmap::Integrity.for(body.dup.force_encoding(Encoding::UTF_8)),
                 Importmap::Integrity.for(body)
  end

  test "for returns a single-line hash" do
    assert_not_includes Importmap::Integrity.for("x" * 1_000), "\n"
  end

  test "hash? tells a computed hash from the booleans a pin can carry" do
    assert Importmap::Integrity.hash?(KNOWN_SHA384)
    assert_not Importmap::Integrity.hash?(true)
    assert_not Importmap::Integrity.hash?(false)
    assert_not Importmap::Integrity.hash?(nil)
  end
end
