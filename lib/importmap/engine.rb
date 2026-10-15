# frozen_string_literal: true

require "importmap/map"
require "importmap/early_hints"

# Use Rails.application.importmap to access the map
Rails::Application.send(:attr_accessor, :importmap)

module Importmap
  class Engine < ::Rails::Engine
    config.importmap = ActiveSupport::OrderedOptions.new
    config.importmap.paths = []
    config.importmap.sweep_cache = Rails.env.development? || Rails.env.test?
    config.importmap.cache_sweepers = []
    config.importmap.rescuable_asset_errors = []
    config.importmap.preload_strategy = :all
    config.importmap.early_hints = true
    config.importmap.finalize = true

    config.autoload_once_paths = %W( #{root}/app/helpers #{root}/app/controllers )

    initializer "importmap" do |app|
      app.importmap = Importmap::Map.new
      app.config.importmap.paths << app.root.join("config/importmap.rb")
      app.config.importmap.paths.each { |path| app.importmap.draw(path) }
    end

    initializer "importmap.reloader" do |app|
      unless app.config.cache_classes
        Importmap::Reloader.new.tap do |reloader|
          reloader.execute
          app.reloaders << reloader
          app.reloader.to_run { reloader.execute }
        end
      end
    end

    initializer "importmap.cache_sweeper" do |app|
      if app.config.importmap.sweep_cache && !app.config.cache_classes
        app.config.importmap.cache_sweepers << app.root.join("app/javascript")
        app.config.importmap.cache_sweepers << app.root.join("vendor/javascript")
        app.importmap.cache_sweeper(watches: app.config.importmap.cache_sweepers)

        ActiveSupport.on_load(:action_controller_base) do
          before_action { Rails.application.importmap.cache_sweeper.execute_if_updated }
        end
      end
    end

    initializer "importmap.assets" do |app|
      if app.config.respond_to?(:assets)
        app.config.assets.paths << Rails.root.join("app/javascript")
        app.config.assets.paths << Rails.root.join("vendor/javascript")
      end
    end

    initializer "importmap.concerns" do
      ActiveSupport.on_load(:action_controller_base) do
        extend Importmap::Freshness
      end
    end

    initializer "importmap.helpers" do
      ActiveSupport.on_load(:action_controller_base) do
        helper Importmap::ImportmapTagsHelper
      end
    end

    initializer "importmap.rescuable_asset_errors" do |app|
      if defined?(Propshaft)
        app.config.importmap.rescuable_asset_errors << Propshaft::MissingAssetError
      end

      if defined?(Sprockets::Rails)
        app.config.importmap.rescuable_asset_errors << Sprockets::Rails::Helper::AssetNotFound
      end
    end

    # Once the app has booted, in every environment, its map is finalized:
    # every pin is deeply frozen (Ractor-shareable), and so is every set of
    # pins a development reload, a cache sweep or a later pin publishes, so
    # reloading works as before. Registered from an initializer, so it runs
    # after the after_initialize blocks of config/application.rb and the
    # environment files.
    initializer "importmap.finalize" do |app|
      app.config.after_initialize do
        app.importmap.finalize! if app.config.importmap.finalize
      end
    end
  end
end
