require_relative '../test_script_suite'

module InfernoTemplate
  class AuCoreSuite < TestScriptSuite
    id :au_core
    title 'AU Core TestScript'

    # AU terminology (SNOMED CT-AU, AMT, ...) is served by the Australian terminology server
    testscripts 'au-core', igs: ['hl7.fhir.au.core#2.0.0'], tx_server: 'https://tx.hl7.org.au/fhir'
  end
end
