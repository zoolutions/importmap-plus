# frozen_string_literal: true

# conformance-kit's audit.require: boots the dummy app, then loads the engine's
# app/ and every file under lib/importmap, so `conformance-audit --strict` sees
# all of Importmap. commands.rb is the CLI: it starts Thor on ARGV when loaded.
ENV["RAILS_ENV"] ||= "test"
require_relative "dummy/config/environment"
Importmap::Engine.eager_load!
# app/helpers and app/controllers are the engine's autoload_once_paths, which
# eager_load! leaves alone.
Importmap::Freshness
Importmap::ImportmapTagsHelper
Dir[File.expand_path("../lib/importmap/**/*.rb", __dir__)].sort.each do |file|
  require file unless file.end_with?("/commands.rb")
end
