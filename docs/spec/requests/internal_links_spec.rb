# frozen_string_literal: true

require "rails_helper"

# Pages cross-link each other by slug and by section anchor, and a section
# anchor is derived from its heading — so renaming or moving a section breaks
# every link pointing at it, silently, in a file nobody touched. This renders
# every page and follows every /docs/… link it emits back to a real page and a
# real id.
RSpec.describe "Internal doc links", type: :request do
  # Only the anchor's own characters: the closing quote ends the match, so a
  # link with no anchor captures nil rather than the rest of the attribute.
  let(:link_regexp) { %r{href="/docs/([a-z0-9\-]+)(?:\#([a-zA-Z0-9\-]+))?"} }

  let(:pages) { Doc.all.select(&:view_class) }

  it "points every link at a page that exists, and every anchor at an id on it" do
    rendered = pages.to_h do |doc|
      get "/docs/#{doc.slug}"
      expect(response).to have_http_status(:ok)
      [ doc.slug, response.body ]
    end

    ids = rendered.transform_values { |body| Nokogiri::HTML(body).css("[id]").map { |node| node["id"] }.to_set }
    broken = []

    rendered.each do |slug, body|
      body.scan(link_regexp) do |target, anchor|
        if !ids.key?(target)
          broken << "#{slug} → /docs/#{target} (no such page)"
        elsif anchor && !ids[target].include?(anchor)
          broken << "#{slug} → /docs/#{target}##{anchor} (no such anchor)"
        end
      end
    end

    expect(broken.uniq).to eq([])
  end
end
