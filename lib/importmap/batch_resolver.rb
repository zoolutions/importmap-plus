require "importmap/provider_chain"

# Resolves a group of specs against a CDN, batch first and then one at a time.
#
# The batch is the fast path and stays: one round trip, and jspm resolves the
# specs' shared dependencies as a single graph, which is what upstream does.
# But a CDN answers a batch as a whole — one spec its generator can't build is
# "no" for all of them — so a refused batch of more than one spec says nothing
# about the specs in it. Each is then asked on its own, along the path it would
# have taken alone: through the chain when the group named no CDN, of the same
# provider once when it did. A package that was always going to resolve is
# pinned from the CDN it was always going to be pinned from, whatever its
# siblings did.
#
# Specs nobody could resolve are collected rather than raised: each pin is
# independent of the others, so the rest still land and the exit code says the
# command didn't do all it was asked.
class Importmap::BatchResolver
  # The specs no CDN answered for, in the order they were asked.
  attr_reader :unresolved

  # +on_miss+ is the command's own "couldn't find" reporter, so the sentence a
  # single spec gets is written in exactly one place.
  def initialize(packager, on_miss:, chain: Importmap::ProviderChain.new)
    @packager   = packager
    @on_miss    = on_miss
    @chain      = chain
    @unresolved = []
  end

  # Yields [ package, url ] for everything that resolved, as it resolves, so a
  # spec that fails later can't discard the work of one that succeeded earlier.
  def each_import(specs, env:, from:, fallback:, &block)
    @named = specs.map { |spec| @packager.package_key_for(spec) }
    @seen  = {}

    if specs.one?
      resolve_one(specs.first, env: env, from: from, fallback: fallback, &block)
    elsif (response = resolve_batch(specs, env: env, from: from, fallback: fallback))
      emit(specs, response, &block)
    else
      specs.each { |spec| resolve_one(spec, env: env, from: from, fallback: fallback, &block) }
    end
  end

  private
    # The batch a group with no CDN of its own sends goes to jspm alone. Handing
    # the whole list to the next CDN is what moved a healthy package's provenance
    # when a sibling failed; the specs travel the rest of the chain separately.
    def resolve_batch(specs, env:, from:, fallback:)
      provider = fallback ? Importmap::ProviderChain::DEFAULT : from
      error    = nil

      response =
        begin
          @packager.import(*specs, env: env, from: provider)
        rescue Importmap::Packager::Error => raised
          error = raised
          nil
        end

      return response if response

      report_split(specs, provider, error&.message || @packager.last_import_error, fallback)
      nil
    end

    def report_split(specs, provider, reason, fallback)
      detail = Importmap::ProviderChain.tidy_reason(reason)
      miss   = if fallback
        %(#{provider} couldn't resolve #{quoted(specs)})
      else
        %(Couldn't find any packages in #{specs.inspect} on #{provider})
      end

      puts miss + (detail ? %( (#{detail})) : "") + "; asking for each on its own"
    end

    def resolve_one(spec, env:, from:, fallback:, &block)
      source = fallback ? Importmap::ProviderChain.to_sentence : from

      if (response = request_one(spec, env: env, from: from, fallback: fallback))
        emit([ spec ], response, &block)
      else
        # A chain that came up empty has already said why each CDN couldn't.
        @on_miss.call([ spec ], source, reason: fallback ? nil : @packager.last_import_error)
        @unresolved << spec
      end
    rescue Importmap::Packager::Error => error
      puts %(Couldn't resolve "#{spec}" from #{source}: #{error.message})
      @unresolved << spec
    end

    def request_one(spec, env:, from:, fallback:)
      if fallback
        @chain.resolve(@packager, [ spec ], env: env) { |_provider, response| response }
      else
        @packager.import(spec, env: env, from: from)
      end
    end

    # Split responses overlap: each carries the dependencies of its own spec.
    # A spec the user named answers for itself, so a sibling's response naming
    # it is a dependency edge and not the answer asked for. Anything else is
    # taken from the first response that carried it, because rewriting it to a
    # second URL would move a package the user never mentioned.
    def emit(specs, response, &block)
      asked_for = specs.map { |spec| @packager.package_key_for(spec) }

      response[:imports].each do |package, url|
        next if @named.include?(package) && !asked_for.include?(package)

        if (kept = @seen[package])
          report_kept(package, kept, url, specs.first) unless kept == url
        else
          @seen[package] = url
          block.call(package, url)
        end
      end
    end

    def report_kept(package, kept, url, spec)
      puts %(Keeping "#{package}" at #{version(kept)} ("#{spec}" resolved it to #{version(url)}))
    end

    def version(url)
      @packager.extract_package_version_from(url) || url
    end

    def quoted(specs)
      specs.map { |spec| %("#{spec}") }.join(", ")
    end
end
