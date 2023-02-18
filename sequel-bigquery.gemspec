# frozen_string_literal: true

require_relative 'lib/sequel_bigquery/version'

Gem::Specification.new do |spec|
  spec.name          = 'sequel-bigquery'
  spec.version       = Sequel::Bigquery::VERSION
  spec.authors       = ['Brendan Weibrecht']
  spec.email         = ['brendan@weibrecht.net.au']

  spec.summary       = "A Sequel adapter for Google's BigQuery"
  spec.homepage      = 'https://github.com/ZimbiX/sequel-bigquery'
  spec.required_ruby_version = Gem::Requirement.new('>= 3.0.0')

  spec.metadata['homepage_uri'] = spec.homepage
  spec.metadata['source_code_uri'] = spec.homepage
  spec.metadata['changelog_uri'] = "#{spec.homepage}/releases"

  spec.license = 'MIT'

  spec.files = Dir.glob(
    %w[
      exe/**/*
      lib/**/*
      README.md
    ],
  )
  spec.bindir        = 'exe'
  spec.executables   = spec.files.grep(%r{\Aexe/}) { |f| File.basename(f) }
  spec.require_paths = ['lib']

  spec.add_dependency 'amazing_print', '~> 1.3'
  spec.add_dependency 'google-cloud-bigquery', '~> 1.35'
  spec.add_dependency 'paint', '~> 2.2'
  spec.add_dependency 'sequel', '~> 5.63'
end
