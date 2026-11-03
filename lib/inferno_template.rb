require_relative 'inferno_template/test_script_suite'

Dir[File.join(__dir__, 'inferno_template', 'suites', '*.rb')].each { |path| require path }

require_relative 'inferno_template/metadata'
