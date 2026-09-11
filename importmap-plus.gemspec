require_relative "lib/importmap/version"

Gem::Specification.new do |spec|
  spec.name        = "importmap-plus"
  spec.version     = Importmap::VERSION
  spec.authors     = [ "David Heinemeier Hansson", "Mikael Henriksson" ]
  spec.email       = "mikael@mhenrixon.com"
  spec.homepage    = "https://github.com/zoolutions/importmap-plus"
  spec.summary     = "importmap-rails with vendoring that minifies, bundles from esm.run, and remembers where each package came from."
  spec.description = "A drop-in replacement for importmap-rails. Same Importmap:: API, same pins, " \
                     "same import map, plus `bin/importmap pin --minify`, `--from esm.run` for " \
                     "jsDelivr's bundled builds, and a pin comment that records the CDN and " \
                     "minification so later updates keep them. Use this gem or importmap-rails, never both."
  spec.license     = "MIT"

  spec.metadata["homepage_uri"]    = spec.homepage
  spec.metadata["source_code_uri"] = spec.homepage
  spec.metadata["changelog_uri"]   = "#{spec.homepage}/blob/main/CHANGELOG.md"

  spec.files = Dir["{app,lib}/**/*", "MIT-LICENSE", "Rakefile", "README.md", "CHANGELOG.md"]

  spec.required_ruby_version = ">= 3.1.0"
  spec.add_dependency "railties", ">= 6.0.0"
  spec.add_dependency "activesupport", ">= 6.0.0"
  spec.add_dependency "actionpack", ">= 6.0.0"
end
