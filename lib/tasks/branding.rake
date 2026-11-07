# frozen_string_literal: true

# Isolated, opt-in branding configuration for self-hosted installations.
#
# This task maps a small set of BRANDING_* environment variables onto the
# matching installation config values. It is deliberately kept in its own file
# so that upstream updates never conflict with it, and it is a no-op when the
# variables are not defined.
#
# Only the config keys that are actually supported by Chatwoot Community
# Edition are mapped here. Enterprise-only white-labelling features (custom
# colour palettes, custom domains, ...) are intentionally NOT emulated.
namespace :branding do
  desc 'Apply branding overrides from environment variables to installation configs'
  task apply_env: :environment do
    mapping = {
      'BRANDING_INSTALLATION_NAME' => 'INSTALLATION_NAME',
      'BRANDING_NAME' => 'BRAND_NAME',
      'BRANDING_LOGO_URL' => 'LOGO',
      'BRANDING_LOGO_DARK_URL' => 'LOGO_DARK',
      'BRANDING_LOGO_THUMBNAIL_URL' => 'LOGO_THUMBNAIL',
      'BRANDING_URL' => 'BRAND_URL',
      'BRANDING_WIDGET_URL' => 'WIDGET_BRAND_URL',
      'BRANDING_TERMS_URL' => 'TERMS_URL',
      'BRANDING_PRIVACY_URL' => 'PRIVACY_URL'
    }

    applied = []

    mapping.each do |env_key, config_name|
      value = ENV.fetch(env_key, nil)
      next if value.nil? || value.strip.empty?

      config = InstallationConfig.find_or_initialize_by(name: config_name)
      next if config.value == value

      config.value = value
      config.save!
      applied << config_name
    end

    GlobalConfig.clear_cache

    if applied.empty?
      puts '[branding] no overrides applied'
    else
      puts "[branding] applied overrides: #{applied.join(', ')}"
    end
  end
end
