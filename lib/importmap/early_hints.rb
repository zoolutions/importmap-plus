# The modulepreload links of javascript_importmap_tags, sent ahead of the
# response as 103 Early Hints.
#
# A link in the body can only be acted on once the browser has parsed that far
# into the HTML, so the whole module graph waits on the response. The same list
# sent as a Link header before the response starts lets the fetches begin while
# the app is still rendering — which is what Rails' own javascript_include_tag
# and stylesheet_link_tag already do for their assets.
#
# `request.send_early_hints` is `env["rack.early_hints"]&.call(links)`: a no-op
# unless the server put the callable there (Puma does with `early_hints true`),
# so on a server without it this costs one joined string and nothing else.
module Importmap::EarlyHints
  class << self
    # `view` is the view rendering the tags — the request and response are read
    # off it the way ActionView's own send_preload_links_header reads them, so a
    # context that has neither is left alone. `packages` is a
    # preloaded_module_packages hash, resolved asset path to the package behind
    # it, which makes the hinted set exactly the tags' set.
    def send_modulepreload_links(view, packages)
      return if packages.empty? || !enabled? || sending?(view)

      request = view.request if view.respond_to?(:request)
      return unless request.respond_to?(:send_early_hints)

      request.send_early_hints("link" => link_header_for(packages.keys))
    end

    private
      # No integrity parameter: browsers don't honour one on a Link header, and
      # the modulepreload tag in the body still carries it, which is where the
      # hash has to match anyway.
      def link_header_for(paths)
        paths.collect { |path| "<#{path}>; rel=modulepreload" }.join(", ")
      end

      # A 103 is a response of its own, written to the socket before the real
      # one. Under `render stream: true` the layout renders while the 200 is
      # already going out, and a hint sent then lands in the middle of the body.
      def sending?(view)
        return false unless view.respond_to?(:response)

        (response = view.response).respond_to?(:sending?) && response.sending?
      end

      def enabled?
        Rails.application.config.importmap.early_hints
      end
  end
end
