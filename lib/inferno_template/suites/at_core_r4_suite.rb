require_relative '../test_script_suite'

module InfernoTemplate
  class AtCoreR4Suite < TestScriptSuite
    id :at_core_r4
    title 'AT Core R4 TestScript'

    # The scripts' profiles (https://fhir.hl7.at/core/r4/...) are in the 2.1.0 CI build, not the published 2.0.0
    testscripts 'at-core-r4', igs: ['igs/hl7.at.fhir.core.r4-2.1.0.tgz']
  end
end
