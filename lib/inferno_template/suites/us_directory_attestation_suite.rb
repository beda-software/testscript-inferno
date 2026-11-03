require_relative '../test_script_suite'

module InfernoTemplate
  class UsDirectoryAttestationSuite < TestScriptSuite
    id :us_directory_attestation
    title 'US Directory Attestation TestScript'

    testscripts 'us-directory-attestation'
  end
end
