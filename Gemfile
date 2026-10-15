source 'https://rubygems.org'
git_source(:github) { |repo| "https://github.com/#{repo}.git" }

# Specify your gem's dependencies in importmap-plus.gemspec.
gemspec

gem "rails"
gem "propshaft", ">= 1.2.0"

gem "sqlite3"

group :development do
  gem "appraisal"
end

group :test do
  gem "minitest-mock"
  # The kit needs Ruby 3.2+; the 3.1 lanes run without it (Bundler resolves
  # required_ruby_version even inside install_if, so a plain guard it is).
  gem "conformance-kit", "~> 0.3", require: false if Gem::Version.new(RUBY_VERSION) >= Gem::Version.new("3.2") # concurrency conformance gates (zoolutions/phlex-reactive#363)
  gem "turbo-rails"
  gem "stimulus-rails"

  gem "byebug"

  gem "rexml"
  gem "capybara"
end
