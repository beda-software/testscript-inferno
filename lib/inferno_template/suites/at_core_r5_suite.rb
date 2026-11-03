require_relative '../test_script_suite'

module InfernoTemplate
  class AtCoreR5Suite < TestScriptSuite
    id :at_core_r5
    title 'AT Core R5 TestScript'

    # R5 scripts: the validator runs as FHIR R5, with the 2.1.0 CI build (the published 2.0.0
    # lacks the scripts' https://fhir.hl7.at/core/r5/... profiles)
    testscripts 'at-core-r5', igs: ['igs/hl7.at.fhir.core.r5-2.1.0.tgz'], validator_context: { sv: '5.0.0' }
  end
end
