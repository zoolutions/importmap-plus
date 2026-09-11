# The entry point Bundler requires for `gem "importmap-plus"`. The constants
# stay under Importmap:: so this gem drops into any app that used
# importmap-rails without touching a single call site.
require "importmap-rails"
