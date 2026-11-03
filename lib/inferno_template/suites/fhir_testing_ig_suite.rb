require_relative '../test_script_suite'

module InfernoTemplate
  class FhirTestingIgSuite < TestScriptSuite
    id :fhir_testing_ig
    title 'FHIR Testing IG TestScript'

    testscripts 'fhir-testing-ig'
  end
end
