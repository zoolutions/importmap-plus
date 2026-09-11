# frozen_string_literal: true

# In-memory registry of the reference docs. One line per page — slug and view
# derive from the title (both overridable), and the sidebar nav derives from
# this registry with zero extra code (see config/initializers/docs_kit.rb's
# `nav_registries`). It also feeds the AI surfaces (/llms.txt, /llms-full.txt,
# search, MCP): an unwritten page (whose view class doesn't resolve yet) is
# silently skipped everywhere.
#
# Add a page with `rails g docs_kit:page "Title" --group=…`, which appends the
# `page` line here and writes the class under app/views/docs/pages/. Uses
# DocsKit::Registry for the shared all/from_slug/grouped/nav_items API.
class Doc
  extend DocsKit::Registry
  path_prefix    "/docs"
  view_namespace "Views::Docs::Pages"

  # Getting started
  page "Overview",             group: "Getting started"
  page "Installation",         group: "Getting started"
  page "How import maps work", group: "Getting started", slug: "how-import-maps-work", view: "HowImportMapsWork"

  # Vendoring
  page "Pinning packages",     group: "Vendoring", slug: "pinning", view: "Pinning"
  page "esm.run bundles",      group: "Vendoring", slug: "esm-run", view: "EsmRun"
  page "Minifying",            group: "Vendoring"
  page "Provenance",           group: "Vendoring"
  page "Locking versions",     group: "Vendoring", slug: "locking", view: "Locking"
  page "Updating & auditing",  group: "Vendoring", slug: "updating", view: "Updating"

  # Serving
  page "Preloading",            group: "Serving"
  page "Subresource integrity", group: "Serving", slug: "integrity", view: "Integrity"
  page "Composing import maps", group: "Serving", slug: "composing", view: "Composing"
  page "Selective imports",     group: "Serving", slug: "selective-imports", view: "SelectiveImports"
  page "Caching & ETags",       group: "Serving", slug: "caching", view: "Caching"

  # Reference
  page "CLI reference",                 group: "Reference", slug: "cli", view: "Cli"
  page "Configuration",                 group: "Reference"
  page "Upgrading from importmap-rails", group: "Reference", slug: "upgrading", view: "Upgrading"
  page "Changelog",                     group: "Reference"
end
