require_relative '../test_script_suite'

module InfernoTemplate
  class RadiationDoseSummarySuite < TestScriptSuite
    id :radiation_dose_summary
    title 'Radiation Dose Summary TestScript'

    testscripts 'radiation-dose-summary'
  end
end
