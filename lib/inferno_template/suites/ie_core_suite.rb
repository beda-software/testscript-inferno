require_relative '../test_script_suite'

module InfernoTemplate
  class IeCoreSuite < TestScriptSuite
    id :ie_core
    title 'IE Core TestScript'

    testscripts 'ie-core'
  end
end
