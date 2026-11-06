require_relative 'lib/path_coverage/version'

Gem::Specification.new do |s|
  s.name = 'path_coverage'
  s.version = PathCoverage::VERSION
  s.summary = 'Path coverage for Ruby, ' \
              'alongside SimpleCov branch coverage'
  s.description = 'Records which paths each condition and each ' \
                  'method took, and reports the paths never ' \
                  'taken in the terminal and as HTML.'
  s.authors = ['Jon Jagger']
  s.license = 'BSD-2-Clause'
  s.homepage = 'https://github.com/path-coverage/ruby'
  s.files = Dir['lib/**/*'].select { |f| File.file?(f) } +
            %w[README.md LICENSE.md exe/path_coverage_collector]
  s.bindir = 'exe'
  s.executables = ['path_coverage_collector']
  # String#bytesplice arrived in Ruby 3.2.
  s.required_ruby_version = '>= 3.2'
  s.add_dependency 'prism', '~> 1.0'
  s.metadata['rubygems_mfa_required'] = 'true'
end
