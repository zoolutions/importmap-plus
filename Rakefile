require "bundler/setup"

APP_RAKEFILE = File.expand_path("test/dummy/Rakefile", __dir__)
load "rails/tasks/engine.rake"

# No `bundler/gem_tasks`: its `release` task (tag + `gem push` from this machine)
# would merge into the release kit's `rake release[X.Y.Z]` (rakelib/release.rake)
# and publish with a local API key. Releases go through bin/release; the gem is
# built and pushed by release.yml over trusted publishing.

require "rake/testtask"

Rake::TestTask.new(:test) do |t|
  t.libs << 'test'
  t.pattern = 'test/**/*_test.rb'
  t.verbose = false
  t.warning = false
end

task default: :test
