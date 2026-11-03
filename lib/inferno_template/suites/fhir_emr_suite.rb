require_relative '../test_script_suite'

module InfernoTemplate
  # The TestScripts of Beda EMR (https://github.com/beda-software/fhir-emr, resources/tests at
  # 81c7e77). They test the EMR's Aidbox with its seeds (Questionnaires, Patient/patient1) and its
  # SDC $populate/$extract, so run them against a fhir-emr deployment
  class FhirEmrSuite < TestScriptSuite
    id :fhir_emr
    title 'FHIR EMR TestScript'
    description <<~DESCRIPTION
      Runs the TestScripts of [Beda EMR](https://github.com/beda-software/fhir-emr) against a fhir-emr
      deployment: questionnaire $populate and $extract (SDC), and the FHIR TestScript examples.
      They read the EMR's seed Questionnaires and Patient/patient1 from the server.
      #{DESCRIPTION}
    DESCRIPTION

    testscripts 'fhir-emr'
  end
end
