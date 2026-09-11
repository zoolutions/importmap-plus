# frozen_string_literal: true

# The gem's CHANGELOG.md, rendered from the file itself so the two never drift.
# The gem is a path dependency of this app, and CHANGELOG.md ships in the gem.
class Views::Docs::Pages::Changelog < DocsUI::Page
  title "Changelog"
  eyebrow "Reference"

  def lead = "Every importmap-plus release, from the gem's own CHANGELOG.md."

  def content
    DocsUI::Section("Releases") do
      md changelog_markdown
    end
  end

  private

  # The file's own "# Changelog" heading duplicates the page title; drop it.
  def changelog_markdown
    Importmap::Engine.root.join("CHANGELOG.md").read.sub(/\A# Changelog\s*/, "")
  end
end
