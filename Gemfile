# frozen_string_literal: true

source "https://rubygems.org"

gemspec

gem 'testscript_eval', path: 'testscript-eval-ruby'

group :development, :test do
  gem 'debug'
  # `inferno start` runs the web app and worker with foreman; `--watch` restarts them with rerun
  gem 'foreman', require: false
  gem 'rerun', require: false
  gem 'rubocop', '~> 1.9'
  gem 'rubocop-rspec', require: false
end

group :test do
  gem 'database_cleaner-sequel', '~> 1.8'
  gem 'factory_bot', '~> 6.1'
  gem 'rack-test'
  gem 'rspec', '~> 3.10'
  gem 'simplecov', '0.21.2', require: false
  gem 'webmock', '~> 3.11'
end