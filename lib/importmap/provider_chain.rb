require "importmap/packager"

# The CDNs a package that names none of its own is asked of, in order.
#
# jspm is first because its generator builds an ES module for packages that
# ship none, which is the thing an import map needs and the reason
# importmap-rails asks it and nothing else. The same generator also gives up
# outright on packages it can't build — a subpath one dependency doesn't
# export, a module it can't find — and that is a fact about the generator, not
# about the package: jsDelivr publishes a bundle of the very same version.
# So a miss moves to the next CDN rather than ending the run.
#
# Only a package with no CDN of its own travels the chain. An explicit --from
# and the provider a pin's comment records are both choices somebody made, and
# a choice is asked once and reported on.
class Importmap::ProviderChain
  PROVIDERS = [ "jspm", "esm.run", "jsdelivr" ].freeze # :nodoc:
  DEFAULT   = PROVIDERS.first # :nodoc:

  # jspm answers to two names: --from takes "jspm", a pin comment records the
  # provider as Packager::DEFAULT_PROVIDER, "jspm.io".
  class << self
    def default?(provider)
      provider && normalize(provider) == DEFAULT
    end

    def normalize(provider)
      provider.to_s == Importmap::Packager::DEFAULT_PROVIDER ? DEFAULT : provider.to_s
    end

    # Every CDN in the chain, for the sentence that reports a package none of
    # them had: "on jspm, esm.run or jsdelivr".
    def to_sentence
      PROVIDERS.to_sentence(two_words_connector: " or ", last_word_connector: " or ")
    end

    # jspm prefixes its generator's messages with "Error: ", which reads as
    # noise once the sentence around it already says something went wrong.
    def tidy_reason(reason)
      reason.to_s.delete_prefix("Error: ").presence
    end
  end

  def initialize(providers = PROVIDERS)
    @providers = providers
  end

  # Asks each CDN in turn for +specs+ and yields [ provider, response ] for the
  # first that answers, returning what the block returns. Returns nil when none
  # of them did, having said why each one couldn't.
  #
  # A CDN that answers "no" is a fact about the package, so the next one is
  # asked; one that couldn't be reached at all is a fact about the run, and
  # when that is how the chain ends the error is raised rather than reported as
  # a package nobody has.
  def resolve(packager, specs, env:)
    error = nil

    @providers.each_with_index do |provider, index|
      response =
        begin
          error = nil
          packager.import(*specs, env: env, from: provider)
        rescue Importmap::Packager::Error => raised
          error = raised
          nil
        end

      return yield(provider, response) if response

      report(provider, specs, error&.message || packager.last_import_error, @providers[index + 1])
    end

    raise error if error
  end

  private
    def report(provider, specs, reason, next_provider)
      detail = self.class.tidy_reason(reason)

      puts %(#{provider} couldn't resolve #{quoted(specs)}) +
           (detail ? %( (#{detail})) : "") +
           (next_provider ? %(; trying #{next_provider}) : "")
    end

    def quoted(specs)
      Array(specs).map { |spec| %("#{spec}") }.join(", ")
    end
end
