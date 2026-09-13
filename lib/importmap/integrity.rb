require "digest"

# The subresource-integrity hash of a file, in the form the import map's
# integrity section and a modulepreload link take: "sha384-" and the digest in
# base64. Computed from the bytes a CDN hands back, which are the bytes the
# browser will hash when it loads the module.
#
# pack("m0") rather than Base64.strict_encode64: base64 stopped being a default
# gem in Ruby 3.4, and this gem depends on railties, activesupport and actionpack
# and nothing else.
module Importmap::Integrity
  ALGORITHM = "sha384".freeze

  class << self
    def for(body)
      "#{ALGORITHM}-#{[ Digest::SHA384.digest(body) ].pack("m0")}"
    end

    # A pin's integrity option is true, false, nil or a hash string; only the
    # last is a value this computed, and only it is quoted and printed.
    def hash?(integrity)
      integrity.is_a?(String)
    end
  end
end
