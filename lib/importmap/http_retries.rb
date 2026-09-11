require "net/http"
require "openssl"

# Retries an outbound request on the failures a CDN or a registry hands out
# under load — a reset connection, a timeout, a 429 or a 5xx — a bounded
# number of times with a growing pause. Included by Packager and Npm, each of
# which raises its own HTTPError once the attempts are spent.
module Importmap::HttpRetries
  RETRYABLE_ERRORS = [ SocketError, SystemCallError, Timeout::Error, EOFError, OpenSSL::SSL::SSLError, Net::ProtocolError ].freeze # :nodoc:
  RETRYABLE_CODES  = %w[ 429 500 502 503 504 ].freeze # :nodoc:

  singleton_class.attr_accessor :attempts, :wait
  self.attempts = 3
  self.wait = 0.5

  private
    def with_retries(description)
      attempt = 0

      loop do
        attempt += 1

        begin
          response = yield
          return response unless attempt < Importmap::HttpRetries.attempts && RETRYABLE_CODES.include?(response.code.to_s)
        rescue *RETRYABLE_ERRORS => error
          unless attempt < Importmap::HttpRetries.attempts
            raise self.class::HTTPError, "Unexpected transport error #{description} (#{error.class}: #{error.message})"
          end
        end

        sleep Importmap::HttpRetries.wait * attempt
      end
    end
end
