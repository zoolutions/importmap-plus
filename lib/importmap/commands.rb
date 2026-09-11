require "thor"
require "importmap/packager"
require "importmap/npm"

class Importmap::Commands < Thor
  include Thor::Actions

  def self.exit_on_failure?
    false
  end

  desc "pin [*PACKAGES]", "Pin new packages"
  option :env, type: :string, aliases: :e, default: "production"
  option :from, type: :string, aliases: :f, desc: "CDN to resolve from: jspm (default), unpkg, jsdelivr, esm.sh, skypack or esm.run"
  option :preload, type: :string, repeatable: true, desc: "Can be used multiple times"
  option :remote, type: :boolean, default: false, desc: "Pin to the remote URL instead of vendoring a download"
  option :minify, type: :boolean, desc: "Minify the vendored download with bun, esbuild or terser"
  def pin(*packages)
    for_each_import_grouped_by_provider(packages, env: options[:env], from: options[:from]) do |package, url|
      pin_package(package, url, preload: options[:preload], remote: options[:remote], env: options[:env],
                                minify: options[:minify], from: options[:from])
    end
  end

  desc "unpin [*PACKAGES]", "Unpin existing packages"
  option :env, type: :string, aliases: :e, default: "production"
  option :from, type: :string, aliases: :f, default: "jspm"
  def unpin(*packages)
    for_each_import(packages, env: options[:env], from: options[:from]) do |package, url|
      if packager.packaged?(package)
        puts %(Unpinning and removing "#{package}")
        packager.remove(package)
      end
    end
  end

  desc "pristine", "Redownload all pinned packages"
  option :env, type: :string, aliases: :e, default: "production"
  option :from, type: :string, aliases: :f, desc: "CDN to resolve from; defaults to the one each package was vendored from"
  option :minify, type: :boolean, desc: "Minify every download; defaults to what each vendored file already is"
  def pristine
    packages = prepare_packages_with_versions

    for_each_import_grouped_by_provider(packages, env: options[:env], from: options[:from]) do |package, url|
      if packager.remote_pin?(package)
        puts %(Skipping "#{package}" (pinned to remote URL))
      else
        minify = options[:minify].nil? ? vendored_minified?(package) : options[:minify]

        puts %(Downloading "#{package}" to #{packager.vendor_path}/#{package}.js from #{url}#{" (minified)" if minify})

        pin_esm_run_dependencies packager.download(package, url, minify: minify), minify: minify
        record_provenance(package, url, minify) if provenance_changed?(package, url, minify)
      end
    end
  end

  desc "json", "Show the full importmap in json"
  def json
    require Rails.root.join("config/environment")
    puts Rails.application.importmap.to_json(resolver: ActionController::Base.helpers)
  end

  desc "audit", "Run a security audit"
  def audit
    vulnerable_packages = npm.vulnerable_packages

    if vulnerable_packages.any?
      table = [["Package", "Severity", "Vulnerable versions", "Vulnerability"]]
      vulnerable_packages.each { |p| table << [p.name, p.severity, p.vulnerable_versions, p.vulnerability] }

      puts_table(table)
      vulnerabilities = 'vulnerability'.pluralize(vulnerable_packages.size)
      severities = vulnerable_packages.map(&:severity).tally.sort_by(&:last).reverse
                                      .map { |severity, count| "#{count} #{severity}" }
                                      .join(", ")
      puts "  #{vulnerable_packages.size} #{vulnerabilities} found: #{severities}"

      exit 1
    else
      puts "No vulnerable packages found"
    end
  end

  desc "outdated", "Check for outdated packages"
  def outdated
    if (outdated_packages = npm.outdated_packages).any?
      table = [["Package", "Current", "Latest"]]
      outdated_packages.each { |p| table << [p.name, p.current_version, p.latest_version || p.error] }

      puts_table(table)
      packages = 'package'.pluralize(outdated_packages.size)
      puts "  #{outdated_packages.size} outdated #{packages} found"

      exit 1
    else
      puts "No outdated packages found"
    end
  end

  desc "update", "Update outdated package pins"
  def update
    if (outdated_packages = npm.outdated_packages).any?
      for_each_import_grouped_by_provider(outdated_packages.map(&:name), env: "production") do |package, url|
        pin_package(package, url)
      end
    else
      puts "No outdated packages found"
    end
  end

  desc "packages", "Print out packages with version numbers"
  def packages
    puts npm.packages_with_versions.map { |x| x.join(' ') }
  end

  private
    def packager
      @packager ||= Importmap::Packager.new
    end

    def npm
      @npm ||= Importmap::Npm.new
    end

    def pin_package(package, url, preload: nil, remote: false, env: "production", minify: nil, from: nil)
      existing_options = packager.extract_existing_pin_options(package)[package] || {}
      preload = existing_options[:preload] if preload.nil?
      integrity = existing_options[:integrity]
      existing_url = existing_options[:to] if existing_options[:to].to_s.match?(Importmap::Packager::REMOTE_URL_REGEXP)

      if existing_url
        repin_remote_package(package, url, existing_url, preload, env: env, from: from, integrity: integrity)
      elsif remote
        pin_remote_package(package, url, preload, integrity: integrity)
      else
        pin_vendored_package(package, url, preload, minify: minify, integrity: integrity)
      end
    end

    def pin_vendored_package(package, url, preload, minify: nil, integrity: nil)
      minify = vendored_minified?(package) if minify.nil?

      puts %(Pinning "#{package}" to #{packager.vendor_path}/#{package}.js via download from #{url}#{" (minified)" if minify})

      dependencies = packager.download(package, url, minify: minify)

      update_importmap_with_pin(package, packager.vendored_pin_for(package, url, preload, minify: minify, integrity: integrity))

      pin_esm_run_dependencies(dependencies, preload: preload, minify: minify)
    end

    # An esm.run bundle imports its dependencies as bare specifiers after
    # download, so each one needs a pin. Pins the app already has win: the
    # bundle then resolves to whatever version the app chose.
    def pin_esm_run_dependencies(dependencies, preload: nil, minify: nil)
      dependencies.each do |dependency, url|
        if packager.packaged?(dependency)
          puts %(Keeping existing pin for "#{dependency}" (bundle was built against #{packager.extract_package_version_from(url)}))
        else
          pin_package(dependency, url, preload: preload, minify: minify)
        end
      end
    end

    # pristine can change where a package comes from (--from) or whether it is
    # minified (--minify) without re-resolving its pin, so rewrite just the
    # comment those are recorded in. Left alone otherwise: a pin may carry
    # options, such as integrity, that a rewrite would drop.
    def record_provenance(package, url, minify)
      existing_options = packager.extract_existing_pin_options(package)[package] || {}

      update_importmap_with_pin(package, packager.vendored_pin_for(package, url, existing_options[:preload],
                                                                   minify: minify, integrity: existing_options[:integrity]))
    end

    def provenance_changed?(package, url, minify)
      current = packager.pin_provenance(package) || {}
      desired = packager.provenance_for(url, minify: minify)

      current.values_at(:provider, :minified) != desired.values_at(:provider, :minified)
    end

    def vendored_minified?(package)
      packager.pin_provenance(package)&.dig(:minified) || false
    end

    # A vendored package keeps coming from the CDN its pin comment names, the
    # way a remote pin keeps its provider, unless --from says otherwise.
    # Packages that aren't pinned yet resolve from jspm.
    def for_each_import_grouped_by_provider(packages, env:, from: nil, &block)
      packages.group_by { |spec| from || vendored_provider_for(spec) || "jspm" }.each do |provider, group|
        for_each_import(group, env: env, from: provider, &block)
      end
    end

    def vendored_provider_for(spec)
      packager.pin_provenance(packager.package_key_for(spec))&.dig(:provider)
    end

    def pin_remote_package(package, url, preload, integrity: nil)
      puts %(Pinning "#{package}" to #{url})

      packager.remove_existing_package_file(package)

      update_importmap_with_pin(package, packager.pin_for(package, url, preloads: preload, integrity: integrity))
    end

    def repin_remote_package(package, url, existing_url, preload, env:, from: nil, integrity: nil)
      # `url` was already resolved from the requested CDN, so an explicit
      # --from moves the pin instead of being overruled by its current one.
      return pin_remote_package(package, url, preload, integrity: integrity) if from

      provider = packager.provider_for_url(existing_url)

      if provider.nil?
        puts %(Skipping "#{package}" pinned to custom URL #{existing_url})
      elsif provider == packager.provider_for_url(url)
        pin_remote_package(package, url, preload, integrity: integrity)
      elsif (provider_url = resolve_url_from_provider(package, url, provider, env: env))
        pin_remote_package(package, provider_url, preload, integrity: integrity)
      else
        puts %(Keeping "#{package}" pinned to #{existing_url} (couldn't resolve it from #{provider}))
      end
    end

    def resolve_url_from_provider(package, reference_url, provider, env:)
      version  = packager.extract_package_version_from(reference_url)
      response = packager.import("#{package}#{version}", env: env, from: provider)

      response && response[:imports][package]
    rescue Importmap::Packager::Error => error
      puts %(Failed to resolve "#{package}" from #{provider}: #{error.message})
      nil
    end

    def update_importmap_with_pin(package, pin)
      new_pin = "#{pin}\n"

      if packager.packaged?(package)
        gsub_file("config/importmap.rb", Importmap::Map.pin_line_regexp_for(package), pin, verbose: false)
      else
        append_to_file("config/importmap.rb", new_pin, verbose: false)
      end

      packager.reload!
    end

    def handle_package_not_found(packages, from)
      puts "Couldn't find any packages in #{packages.inspect} on #{from}"
    end

    def remove_line_from_file(path, pattern)
      path = File.expand_path(path, destination_root)

      all_lines = File.readlines(path)
      with_lines_removed = all_lines.select { |line| line !~ pattern }

      File.open(path, "w") do |file|
        with_lines_removed.each { |line| file.write(line) }
      end
    end

    def puts_table(array)
      column_sizes = array.reduce([]) do |lengths, row|
        row.each_with_index.map{ |iterand, index| [lengths[index] || 0, iterand.to_s.length].max }
      end

      divider = "|" + (column_sizes.map { |s| "-" * (s + 2) }.join('|')) + '|'
      array.each_with_index do |row, row_number|
        row = row.fill(nil, row.size..(column_sizes.size - 1))
        row = row.each_with_index.map { |v, i| v.to_s + " " * (column_sizes[i] - v.to_s.length) }
        puts "| " + row.join(" | ") + " |"
        puts divider if row_number == 0
      end
    end

    def prepare_packages_with_versions(packages = [])
      if packages.empty?
        npm.packages_with_versions.map do |p, v|
          v.blank? ? p : [p, v].join("@")
        end
      else
        packages
      end
    end

    def for_each_import(packages, **options, &block)
      response = packager.import(*packages, **options)

      if response
        response[:imports].each(&block)
      else
        handle_package_not_found(packages, options[:from])
      end
    end
end

Importmap::Commands.start(ARGV)
