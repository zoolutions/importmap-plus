require "thor"
require "importmap/packager"
require "importmap/package_graph"
require "importmap/vendored_graph"
require "importmap/npm"
require "importmap/provider_chain"
require "importmap/integrity"

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
  option :lock, type: :boolean, desc: "Lock the pin at this version; update, pin and pristine leave it there until unlocked"
  option :force, type: :boolean, default: false, desc: "Re-pin locked packages, keeping each lock at the new version"
  option :vendor, type: :boolean, default: false, desc: "Vendor the download even when it looks like it needs sibling files; converts a pin kept remote back"
  option :integrity, type: :boolean, default: true, desc: "Write a subresource-integrity hash on a pin kept remote; --no-integrity skips the fetch that computes it"
  def pin(*packages)
    packages = resolve_latest_versions(without_locked(packages, lock: options[:lock], force: options[:force]))
    # jspm resolves a package together with its dependencies; --lock and
    # --no-lock are about the packages that were asked for, not those.
    requested = packages.map { |spec| packager.package_key_for(spec) }

    for_each_import_grouped_by_provider(packages, env: options[:env], from: options[:from], fallback: true) do |package, url|
      next if keep_locked_dependency(package, requested)

      pin_package(package, url, preload: options[:preload], remote: options[:remote], env: options[:env],
                                minify: options[:minify], from: options[:from],
                                lock: requested.include?(package) ? options[:lock] : nil,
                                vendor: requested.include?(package) && options[:vendor])
    end
  end

  desc "lock [*PACKAGES]", "Lock packages at their pinned version"
  def lock(*packages)
    exit 1 unless packages.map { |package| lock_package(package) }.all?
  end

  desc "unlock [*PACKAGES]", "Let locked packages be updated again"
  def unlock(*packages)
    exit 1 unless packages.map { |package| unlock_package(package) }.all?
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
    unrestored = []

    for_each_import_grouped_by_provider(packages, env: options[:env], from: options[:from]) do |package, url|
      if packager.remote_pin?(package)
        puts %(Skipping "#{package}" (pinned to remote URL))
      elsif (resolved = version_drift_of_locked(package, url))
        puts %(Skipping "#{package}" (locked at #{packager.pin_provenance(package)[:version]}, CDN resolved #{resolved}))
      else
        unrestored << package unless restore_package(package, url)
      end
    end

    exit 1 if unrestored.any?
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
      locked = outdated_packages.select { |p| locked_pin_covering(p.name) }

      table = [["Package", "Current", "Latest", "Locked"]]
      outdated_packages.each { |p| table << [p.name, p.current_version, p.latest_version || p.error, locked.include?(p) ? "yes" : ""] }

      puts_table(table)
      packages = 'package'.pluralize(outdated_packages.size)
      puts "  #{outdated_packages.size} outdated #{packages} found#{" (#{locked.size} locked)" if locked.any?}"

      # A lock is a version the app chose, so only the rest count as drift.
      exit 1 if locked.size < outdated_packages.size
    else
      puts "No outdated packages found"
    end
  end

  desc "update [*PACKAGES]", "Update outdated package pins"
  option :all, type: :boolean, default: false, desc: "Update every outdated package (the default when no names are given)"
  option :force, type: :boolean, default: false, desc: "Update locked packages too, keeping each lock at the new version"
  def update(*packages)
    if packages.any? && options[:all]
      puts "Pass package names or --all, not both"
      exit 1
    end

    # A package the registry couldn't answer for has no latest_version, so
    # nothing established that it moved: re-pinning would let a blip
    # re-resolve the pin against the CDN and carry it somewhere new. Each
    # pin is independent of the others, so the rest still update; the exit
    # code says the command didn't do all it was asked.
    outdated_packages, unchecked_packages = npm.outdated_packages(only: packages.presence).partition(&:latest_version)
    unchecked_packages.each { |p| puts %(Couldn't check "#{p.name}": #{p.error}) }

    exit 1 unless every_package_known?(packages, outdated_packages, unchecked_packages)

    if outdated_packages.empty?
      puts "No outdated packages found" if unchecked_packages.empty?
    elsif (names = without_locked_updates(outdated_packages.map(&:name), force: options[:force])).empty?
      puts "Nothing to update (every outdated package is locked; pass --force)"
    else
      keys = packages.any? ? requested_keys_for(packages, names) : outdated_keys_for(names)

      for_each_import_grouped_by_provider(keys, env: "production", fallback: true) do |package, url|
        next if keep_locked_dependency(package, keys)

        pin_package(package, url)
      end
    end

    exit 1 if unchecked_packages.any?
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

    # A lock outlives a rewrite unless the caller says otherwise, so update
    # and --force re-lock at the version they move to.
    def pin_package(package, url, preload: nil, remote: false, env: "production", minify: nil, from: nil, lock: nil, vendor: false)
      existing_options = packager.extract_existing_pin_options(package)[package] || {}
      preload = existing_options[:preload] if preload.nil?
      integrity = existing_options[:integrity]
      locked = lock.nil? ? packager.locked?(package) : lock
      # A pin vendored on purpose stays vendored: without this an update would
      # inspect the download again, refuse it again, and quietly undo --vendor.
      vendor ||= packager.vendored?(package)
      # A pin kept remote only because its file imports siblings is vendored
      # again now that the whole graph can be. The reason its comment records
      # is one this gem has since learned to answer, and without this an app
      # that hit the check once would never see the fix arrive.
      regraph = packager.remote_reason(package) == Importmap::PackageGraph::REASON
      existing_url = existing_options[:to] if existing_options[:to].to_s.match?(Importmap::Packager::REMOTE_URL_REGEXP)

      report_graph_shadowing(package)

      if existing_url && !vendor && !regraph
        repin_remote_package(package, url, existing_url, preload, env: env, from: from, integrity: integrity, locked: locked)
      elsif remote
        pin_remote_package(package, url, preload, integrity: integrity, locked: locked)
      else
        pin_vendored_package(package, url, preload, minify: minify, integrity: integrity, locked: locked, vendor: vendor)
      end
    end

    # Nothing is said about a download until it has arrived and been found fit
    # to serve on its own, so a package kept remote reports that and only that.
    def pin_vendored_package(package, url, preload, minify: nil, integrity: nil, locked: false, vendor: false)
      minify = vendored_minified?(package) if minify.nil?

      begin
        dependencies = packager.download(package, url, minify: minify, force: vendor, graph: !vendor)
      rescue Importmap::Packager::Unvendorable, Importmap::Packager::NotAnEsModule => refusal
        return pin_remote_package(package, url, preload, integrity: integrity, locked: locked, kept_remote: refusal)
      rescue Importmap::VendoredGraph::Occupied => occupied
        # Nothing is written, including the pin: the app is asked to move its
        # own directory rather than told afterwards that this gem took it.
        return puts %(Skipping "#{package}": #{occupied.message})
      end

      graph = packager.last_graph

      puts %(Pinning "#{package}" to #{packager.vendor_path}/#{package}.js via download from #{url}#{" (minified)" if minify}#{graph_note(graph)})

      update_importmap_with_pin(package, packager.vendored_pin_for(package, url, preload, minify: minify, integrity: integrity, locked: locked, vendored: vendor))

      # The line that maps the graph directory goes with the download: a
      # package that stopped needing one takes its line and its files with it,
      # or pin_all_from keeps mapping files nothing imports.
      if graph
        update_importmap_with_graph_pin(package, packager.graph_pin_for(package, url, preload))
      else
        packager.remove_graph(package)
      end

      report_lock(package) if locked

      pin_esm_run_dependencies(dependencies, preload: preload, minify: minify)
    end

    # pristine restores what each pin already says, so a package vendored
    # before the single-file check existed — or on purpose with --vendor — is
    # downloaded again rather than converted, and only a pin that already maps
    # a graph directory has one crawled again. pin is where both are decided.
    #
    # A package the CDN can no longer serve the way its pin describes stops
    # that one package being restored, not the run: pristine is the repair
    # command, and the packages after it in the batch still need repairing.
    def restore_package(package, url)
      minify = options[:minify].nil? ? vendored_minified?(package) : options[:minify]

      puts %(Downloading "#{package}" to #{packager.vendor_path}/#{package}.js from #{url}#{" (minified)" if minify})

      dependencies = packager.download(package, url, minify: minify, force: true,
                                                     graph: packager.vendored_graph(package).mapped?)

      # A download that came back as one file — a --from that moved the package
      # to a bundling CDN — takes its graph line with it, or pin_all_from is
      # left mapping the directory that download just removed.
      packager.remove_graph(package) unless packager.last_graph

      pin_esm_run_dependencies dependencies, minify: minify
      record_provenance(package, url, minify) if provenance_changed?(package, url, minify)

      true
    rescue Importmap::Packager::Unvendorable, Importmap::Packager::NotAnEsModule => refusal
      puts %(Couldn't restore "#{package}": it #{refusal.message})
      false
    rescue Importmap::VendoredGraph::Occupied => occupied
      puts %(Couldn't restore "#{package}": #{occupied.message})
      false
    end

    def lock_package(spec)
      package = packager.package_key_for(spec)

      if package != spec
        puts %(Use "bin/importmap pin #{spec} --lock" to lock at a different version)
      elsif !packager.packaged?(package)
        puts %(Couldn't find a pin for "#{package}")
      elsif packager.locked?(package)
        puts %("#{package}" is already locked at #{packager.pin_provenance(package)[:version]})
        return true
      elsif (line = packager.locked_pin_line(package))
        update_importmap_with_pin(package, line)
        report_lock(package)
        return true
      else
        puts %(Can't lock "#{package}": its pin has no version)
      end

      false
    end

    def unlock_package(spec)
      package = packager.package_key_for(spec)

      if !packager.packaged?(package)
        puts %(Couldn't find a pin for "#{package}")
        false
      elsif !packager.locked?(package)
        puts %("#{package}" isn't locked)
        true
      else
        update_importmap_with_pin(package, packager.unlocked_pin_line(package))
        puts %(Unlocked "#{package}")
        true
      end
    end

    def report_lock(package)
      puts %(Locked "#{package}" at #{packager.pin_provenance(package)[:version]})
    end

    # Specs the user named that point at a locked pin are dropped, with a
    # note, unless the lock is what they are here to change.
    def without_locked(specs, lock: nil, force: false)
      return specs if force || !lock.nil?

      specs.reject do |spec|
        package = packager.package_key_for(spec)

        packager.locked?(package).tap { |locked| puts skip_locked_message(package) if locked }
      end
    end

    # update sees npm names (apexcharts) where pins are import-map keys
    # (apexcharts/core), so a lock on any pin of the package holds it.
    def without_locked_updates(names, force: false)
      return names if force

      names.reject do |name|
        (locked = locked_pin_covering(name)).tap { puts skip_locked_message(locked) if locked }
      end
    end

    def skip_locked_message(package)
      %(Skipping "#{package}" (locked at #{packager.pin_provenance(package)[:version]}; run bin/importmap unlock #{package} or pass --force))
    end

    # Says why a named package won't be updated. A name with no pin at all
    # is a typo until proven otherwise, so nothing is updated in that case.
    # One the registry couldn't be asked about was already reported and is
    # no reason to hold back the others.
    def every_package_known?(names, outdated_packages, unchecked_packages)
      versioned = npm.packages_with_versions.to_h
      outdated  = outdated_packages.map(&:name)
      unchecked = unchecked_packages.map(&:name)

      names.map do |name|
        key = packager.package_key_for(name)
        package = packager.package_name_for(key)

        if !packager.packaged?(key)
          puts %(Couldn't find a pin for "#{name}")
          next false
        elsif outdated.include?(package) || unchecked.include?(package)
          next true
        elsif versioned.key?(package)
          puts %("#{name}" is already up to date (#{versioned[package]}))
        else
          puts %(Can't tell whether "#{name}" is outdated: its pin has no version)
        end

        true
      end.all?
    end

    # The registry knows a package by name and the import map by key: a pin of
    # "photoswipe/lightbox" is outdated when "photoswipe" is. A named update
    # re-pins the keys that were asked for: a package name means every pin
    # that carries it, the way outdated reports it and a bare update moves it,
    # while "photoswipe/lightbox" means that one key.
    def requested_keys_for(specs, outdated_names)
      specs.flat_map { |spec| keys_for(packager.package_key_for(spec)) }
           .select { |key| outdated_names.include?(packager.package_name_for(key)) }
    end

    def keys_for(key)
      return [ key ] unless key == packager.package_name_for(key)

      versioned_keys_by_package[key] || [ key ]
    end

    # An outdated package is outdated in every pin that carries it, so a bare
    # update re-pins those keys: "photoswipe" moving updates the app's
    # "photoswipe/lightbox" pin rather than appending a bare one beside it.
    #
    # Only pins that declare a version count, the same ones outdated reports
    # on. An app file pinned under a package's namespace — pin "md5/helpers",
    # to: "md5/helpers.js" — names no version and is none of the registry's
    # business; asking a CDN for it 404s the whole batch and nothing updates.
    #
    # A name no pin's key names is one whose version came from a URL that
    # doesn't match its key (pin "buffer", to: ".../npm:jspm-core@..."); it is
    # still the only handle there is, so it goes through as itself.
    def outdated_keys_for(names)
      names.flat_map { |name| versioned_keys_by_package[name] || [ name ] }
    end

    def versioned_keys_by_package
      packager.pinned_packages.select { |key| packager.pin_version(key) }
                              .group_by { |key| packager.package_name_for(key) }
    end

    def locked_pin_covering(name)
      packager.locked_pins.find { |key| key == name || key.start_with?("#{name}/") }
    end

    # A CDN resolves a package together with its dependencies. One the app has
    # locked stays where it is: only a package named on the command line moves.
    def keep_locked_dependency(package, requested)
      return false if requested.include?(package) || !packager.locked?(package)

      puts %(Keeping existing pin for "#{package}" (locked at #{packager.pin_provenance(package)[:version]}))
      true
    end

    # pristine asks the CDN for the pinned version, so a locked package only
    # drifts if the CDN answers with another one.
    def version_drift_of_locked(package, url)
      return unless packager.locked?(package)

      resolved = packager.extract_package_version_from(url).to_s.delete_prefix("@")
      resolved if resolved != packager.pin_provenance(package)[:version]
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
                                                                   minify: minify, integrity: existing_options[:integrity],
                                                                   vendored: packager.vendored?(package),
                                                                   locked: packager.locked?(package)))
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
    #
    # +fallback+ lets the group that named no CDN try the rest of the chain
    # when jspm can't build it, which is what pin and update want. pristine
    # doesn't: it restores what each pin already says, and a pin that moved to
    # another CDN would be a rewrite, not a restore.
    def for_each_import_grouped_by_provider(packages, env:, from: nil, fallback: false, &block)
      packages.group_by { |spec| from || vendored_provider_for(spec) || Importmap::ProviderChain::DEFAULT }.each do |provider, group|
        if fallback && from.nil? && Importmap::ProviderChain.default?(provider)
          for_each_import_with_fallback(group, env: env, &block)
        else
          for_each_import(group, env: env, from: provider, &block)
        end
      end
    end

    # A package nobody has pinned yet names no CDN, so it is asked of each in
    # turn: jspm's generator giving up on a package says something about the
    # generator, not about the package, and the next CDN often has it. A
    # provider a pin already records, or one --from names, is a choice somebody
    # made, and a choice is asked once and reported on.
    def for_each_import_with_fallback(packages, env:, &block)
      response = Importmap::ProviderChain.new.resolve(packager, packages, env: env) { |_provider, answer| answer }

      if response
        response[:imports].each(&block)
      else
        # Every CDN has already said why it couldn't, so the summary repeats none of it.
        handle_package_not_found(packages, Importmap::ProviderChain.to_sentence, reason: nil)
      end
    end

    # A spec with no version means the latest, and the registry is what knows
    # which that is: a CDN answers with the latest it has got round to indexing,
    # which lags npm by anything from hours to a major release. Resolving it up
    # front also pins the version for the whole chain, so falling back to
    # another CDN can't quietly land the app on a different one. A registry
    # that can't be reached leaves the spec alone, and the CDN chooses as before.
    def resolve_latest_versions(specs)
      specs.map do |spec|
        name, version, _subpath = spec.to_s.match(Importmap::Packager::PACKAGE_SPEC_REGEXP)&.captures
        next spec if version || name.nil?

        if (latest = npm.latest_version(name))
          puts %(Resolved "#{name}" to #{latest} from the npm registry)
          packager.package_spec_for(spec, "@#{latest}")
        else
          spec
        end
      end
    end

    # A subpath pin that names no CDN of its own comes from wherever its
    # package's pin came from: pdfjs-dist and pdfjs-dist/build/pdf.worker.min.mjs
    # were pinned together, and jspm, the default, can't resolve either.
    # A pin answers for itself first and only then for its subpaths: the URL on
    # pin "photoswipe/lightbox" says more about where that file comes from than
    # its package's pin does. Asking the package first grouped the two together,
    # and one spec the CDN can't answer for fails the whole batch.
    def vendored_provider_for(spec)
      key  = packager.package_key_for(spec)
      name = packager.package_name_for(key)

      return packager.pin_provenance(key)&.dig(:provider) || kept_remote_provider(key) if key == name

      provider_of_pin(key) || provider_of_pin(name)
    end

    # A pin the single-file check kept remote records its CDN only in its URL:
    # the comment's provider slot is taken by the reason it was kept. Asking the
    # URL keeps such a pin on its own CDN when it is re-pinned — and, now that a
    # chunked package can be vendored whole, when it converts to a download.
    # A pin the app made remote itself carries no reason and is left to
    # repin_remote_package, which resolves it from its URL as it always did.
    def kept_remote_provider(key)
      return unless packager.remote_reason(key)

      packager.provider_for_url(packager.extract_existing_pin_options(key).dig(key, :to))
    end

    # A vendored pin records its CDN in the version comment; a remote one
    # carries it in the URL and, unlocked, has no comment at all. Only a subpath
    # asks this, and a bare package pin above stops at its comment: reading the
    # URL of every pin would change where a plain remote pin resolves its
    # dependencies from, which is not this lookup's business.
    def provider_of_pin(package)
      packager.pin_provenance(package)&.dig(:provider) ||
        packager.provider_for_url(packager.extract_existing_pin_options(package).dig(package, :to))
    end

    # +kept_remote+ is the Packager's refusal to vendor a download it just
    # fetched — its reasons, and the hash of the bytes it already has; without
    # it the reason the pin already records is carried over, so update and a
    # plain pin don't drop it.
    def pin_remote_package(package, url, preload, integrity: nil, locked: false, kept_remote: nil)
      if compute_integrity?
        integrity = remote_integrity_for(url, integrity, kept_remote&.integrity)
      elsif packager.integrity_hash?(package)
        puts %(Dropping the integrity hash on "#{package}" (--no-integrity))
      end

      notes = +""
      notes << %( (kept remote: #{kept_remote.reasons.to_sentence})) if kept_remote
      notes << %( (integrity #{integrity})) if Importmap::Integrity.hash?(integrity)

      puts %(Pinning "#{package}" to #{url}#{notes})

      remote = kept_remote&.reasons&.first || packager.remote_reason(package)

      packager.remove_existing_package_file(package)
      packager.remove_graph(package)

      update_importmap_with_pin(package, packager.pin_for(package, url, preloads: preload, integrity: integrity,
                                                           locked: locked, remote: remote))
      report_lock(package) if locked
    end

    def repin_remote_package(package, url, existing_url, preload, env:, from: nil, integrity: nil, locked: false)
      # `url` was already resolved from the requested CDN, so an explicit
      # --from moves the pin instead of being overruled by its current one.
      return pin_remote_package(package, url, preload, integrity: integrity, locked: locked) if from

      provider = packager.provider_for_url(existing_url)

      if provider.nil?
        puts %(Skipping "#{package}" pinned to custom URL #{existing_url})
      elsif provider == packager.provider_for_url(url)
        pin_remote_package(package, url, preload, integrity: integrity, locked: locked)
      elsif (provider_url = resolve_url_from_provider(package, url, provider, env: env))
        pin_remote_package(package, provider_url, preload, integrity: integrity, locked: locked)
      else
        puts %(Keeping "#{package}" pinned to #{existing_url} (couldn't resolve it from #{provider}))
      end
    end

    # Read from the command's own options rather than threaded through every
    # pin path: update, pristine and an esm.run bundle's dependency pins all
    # reach pin_remote_package too, and a keyword one of them forgets to pass
    # silently hashes a pin the app asked not to hash. Only pin declares the
    # flag, so anything else sees nil and hashes.
    def compute_integrity?
      options["integrity"] != false
    end

    # A remote pin is the one place an app trusts a CDN at runtime, so the pin
    # records the hash of what was resolved and the browser checks the bytes it
    # gets against it. integrity: false is an app's decision and stays; a hash
    # the line already carried was computed for the old URL and was dropped
    # when the line was read, so nil here means "hash this". +computed+ is the
    # hash a download that was just refused already carries — the file isn't
    # fetched again for it.
    def remote_integrity_for(url, integrity, computed = nil)
      return integrity if integrity == false

      computed || Importmap::Integrity.for(packager.fetch_remote(url))
    rescue Importmap::Packager::Error => error
      puts %(Couldn't hash #{url} (#{error.message}); pinning it without an integrity hash)
      nil
    end

    def resolve_url_from_provider(package, reference_url, provider, env:)
      version  = packager.extract_package_version_from(reference_url)
      response = packager.import(packager.package_spec_for(package, version), env: env, from: provider)

      response && response[:imports][package]
    rescue Importmap::Packager::Error => error
      puts %(Failed to resolve "#{package}" from #{provider}: #{error.message})
      nil
    end

    # Importmap::Map expands a directory over the packages, so a key some other
    # package's graph already maps resolves to that file whatever the pin about
    # to be written says. Say so rather than write a line that does nothing.
    def report_graph_shadowing(package)
      mapped = Importmap::VendoredGraph.mapping_for(importmap_source, package)

      puts %(Note: the graph of "#{mapped}" already maps "#{package}", and a mapped directory wins over a pin) if mapped
    end

    # Two directories mapping one package write their files under the same
    # prefix, so at two versions the app gets one of them for every file the
    # two share, and which one depends on the order of the lines.
    def report_graph_conflict(pin)
      directory, under, version = Importmap::VendoredGraph.mappings_in(pin).first
      conflict = Importmap::VendoredGraph.conflict_in(importmap_source, under: under, version: version, except: directory)

      puts %(Note: #{conflict.first} already maps "#{under}" at #{conflict.last}; a file both carry resolves to one of them) if conflict
    end

    def importmap_source
      File.exist?("config/importmap.rb") ? File.read("config/importmap.rb") : ""
    end

    # How many files came down with the entry, so an app can see that a chunked
    # package was vendored whole rather than as the one file that would 404.
    def graph_note(graph)
      %( (with #{graph.size} sibling #{"file".pluralize(graph.size)})) if graph && graph.size.positive?
    end

    def update_importmap_with_graph_pin(package, pin)
      report_graph_conflict(pin)

      if packager.vendored_graph(package).mapped?
        gsub_file("config/importmap.rb", packager.vendored_graph(package).line_regexp, pin, verbose: false)
      else
        append_to_file("config/importmap.rb", "#{pin}\n", verbose: false)
      end

      packager.reload!
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

    # jspm answers 401 with its generator's reason in the body — the subpath a
    # dependency doesn't export, the module it couldn't find — and that is the
    # one thing that tells an app developer whether to try another CDN.
    def handle_package_not_found(packages, from, reason: packager.last_import_error)
      detail = Importmap::ProviderChain.tidy_reason(reason)

      puts "Couldn't find any packages in #{packages.inspect} on #{from}#{" (#{detail})" if detail}"
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
