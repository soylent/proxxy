# frozen_string_literal: true

require 'pathname'

Gem::Specification.new do |s|
  s.name = 'proxxy'
  s.version = Pathname(__dir__).join('VERSION').read.chomp
  s.summary = 'https proxy'
  s.author = 'soylent'
  s.license = 'MIT'
  s.homepage = 'https://github.com/soylent/proxxy'
  s.files = Dir.glob('lib/*') << 'VERSION'
  s.executables = 'proxxy'
  s.required_ruby_version = '>= 2.5.0'
  s.add_runtime_dependency 'eventmachine', '~> 1.2'
  s.add_development_dependency 'cutest', '~> 1.2'
end
