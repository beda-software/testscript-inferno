require_relative '../test_script_suite'

module InfernoTemplate
  class ErezeptValidatorSuite < TestScriptSuite
    id :erezept_validator
    title 'E-Rezept Validator TestScript'

    testscripts 'erezept-validator'
  end
end
