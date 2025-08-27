source "https://rubygems.org"

# Bundle edge Rails instead: gem "rails", github: "rails/rails", branch: "main"
gem "rails", "~> 8.0.2", ">= 8.0.2.1"
# The modern asset pipeline for Rails [https://github.com/rails/propshaft]
gem "propshaft"
# Use postgresql as the database for Active Record
gem "pg", "~> 1.1"
# Use the Puma web server [https://github.com/puma/puma]
gem "puma", ">= 5.0"
# Use JavaScript with ESM import maps [https://github.com/rails/importmap-rails]
gem "importmap-rails"
# Hotwire's SPA-like page accelerator [https://turbo.hotwired.dev]
gem "turbo-rails"
# Hotwire's modest JavaScript framework [https://stimulus.hotwired.dev]
gem "stimulus-rails"
# Use Tailwind CSS [https://github.com/rails/tailwindcss-rails]
gem "tailwindcss-rails"
# Build JSON APIs with ease [https://github.com/rails/jbuilder]
gem "jbuilder"

# Use Active Model has_secure_password [https://guides.rubyonrails.org/active_model_basics.html#securepassword]
gem "bcrypt", "~> 3.1.7"

# AI Provider gems
gem "anthropic" # Claude
gem "ruby-openai" # GPT-4 and other OpenAI models
gem "google-apis-aiplatform_v1" # Google Gemini
gem "cohere-ruby" # Cohere Command R+
gem "replicate-ruby" # Llama, Mixtral and other open models

# Data processing and connections
gem "csv" # Required for Ruby 3.4+
gem "pg_search" # PostgreSQL full-text search
gem "connection_pool" # Database connection pooling
# gem "mysql2" # MySQL connector - uncomment after installing mysql dependencies
gem "mongo" # MongoDB connector
gem "aws-sdk-s3" # S3 integration
gem "roo" # Excel/CSV processing
gem "caxlsx" # Excel generation

# Security and authentication
gem "devise" # Authentication framework
gem "pundit" # Authorization
gem "jwt" # JSON Web Tokens
gem "rack-attack" # Rate limiting
gem "lockbox" # Encryption for sensitive data

# API and serialization
gem "jsonapi-serializer" # Fast JSON serialization
gem "kaminari" # Pagination
gem "rack-cors" # CORS support

# Monitoring and performance
gem "scout_apm" # Performance monitoring
gem "rollbar" # Error tracking

# Docker and sandboxing
gem "docker-api" # Docker container management

# State machines
gem "aasm" # State machine for analysis workflow

# Windows does not include zoneinfo files, so bundle the tzinfo-data gem
gem "tzinfo-data", platforms: %i[ windows jruby ]

# Use the database-backed adapters for Rails.cache, Active Job, and Action Cable
gem "solid_cache"
gem "solid_queue"
gem "solid_cable"

# Reduces boot times through caching; required in config/boot.rb
gem "bootsnap", require: false

# Deploy this application anywhere as a Docker container [https://kamal-deploy.org]
gem "kamal", require: false

# Add HTTP asset caching/compression and X-Sendfile acceleration to Puma [https://github.com/basecamp/thruster/]
gem "thruster", require: false

# Use Active Storage variants [https://guides.rubyonrails.org/active_storage_overview.html#transforming-images]
# gem "image_processing", "~> 1.2"

group :development, :test do
  # See https://guides.rubyonrails.org/debugging_rails_applications.html#debugging-with-the-debug-gem
  gem "debug", platforms: %i[ mri windows ], require: "debug/prelude"

  # Static analysis for security vulnerabilities [https://brakemanscanner.org/]
  gem "brakeman", require: false

  # Omakase Ruby styling [https://github.com/rails/rubocop-rails-omakase/]
  gem "rubocop-rails-omakase", require: false
end

group :development do
  # Use console on exceptions pages [https://github.com/rails/web-console]
  gem "web-console"
end
