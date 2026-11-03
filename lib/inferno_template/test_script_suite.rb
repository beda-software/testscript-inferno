require_relative 'test_script_group'

module InfernoTemplate
  # Every directory in TestScript/ holds the TestScripts (and their fixtures) of one IG
  TESTSCRIPT_DIR = File.expand_path('../../TestScript', __dir__)

  # Common base of the per-IG suites in suites/: the inputs and the FHIR client. A suite subclasses
  # it, sets its id and title, and calls `testscripts` with its TestScript/<IG> directory:
  #
  #   class AuCoreSuite < TestScriptSuite
  #     id :au_core
  #     title 'AU Core TestScript'
  #     testscripts 'au-core', igs: ['hl7.fhir.au.core#2.0.0'], tx_server: 'https://tx.hl7.org.au/fhir'
  #   end
  class TestScriptSuite < Inferno::TestSuite
    extend TestScriptGroup

    # Inferno requires an id on every TestSuite class, the abstract base included
    id :testscript_suite

    DESCRIPTION = <<~DESCRIPTION.freeze
      Every TestScript is a test group:
      Setup creates its fixtures on the server, each TestScript test is an Inferno test, and
      Teardown deletes the fixtures again. A group runs as a whole, as its tests share the fixtures.
    DESCRIPTION

    input :url,
          title: 'FHIR Server Base Url'

    input :authorization,
          title: 'Authorization header',
          description: 'Sent as is in the Authorization header, e.g. `Basic cm9vdDpzZWNyZXQ=`',
          optional: true

    input :xml_support,
          title: 'Server supports FHIR XML',
          description: 'When a script asks for XML, send and accept XML. Otherwise JSON is used instead.',
          type: 'radio',
          default: 'false',
          optional: true,
          options: { list_options: [{ label: 'Yes', value: 'true' }, { label: 'No', value: 'false' }] }

    fhir_client do
      url :url
      headers({ 'Authorization' => authorization.presence }.compact)
    end

    class << self
      # The TestScript/<IG> directory the suite runs, set by `testscripts`
      attr_reader :testscript_dir

      # Defines a group for every TestScript in TestScript/<dir>, and the FHIR resource validator
      # with the IG packages its `validateProfileId` asserts need and, optionally, the terminology
      # server it checks codes against (the validator's default otherwise). Call it after `id`, as
      # the validator belongs to the suite id
      # `validator_context` adds validator settings, e.g. `{ sv: '5.0.0' }` for R5 scripts
      def testscripts(dir, igs: [], tx_server: nil, validator_context: {})
        @testscript_dir = File.join(TESTSCRIPT_DIR, dir)
        short_title title if short_title.nil?
        description "Runs the #{title} FHIR TestScripts against a FHIR server. #{DESCRIPTION}" if description.nil?

        fhir_resource_validator do
          igs(*igs) if igs.any?
          validation_context(txServer: tx_server) if tx_server
          validation_context(validator_context) if validator_context.any?

          exclude_message do |message|
            message.message.match?(/\A\S+: \S+: URL value '.*' does not resolve/)
          end
        end

        testscript_groups File.join(@testscript_dir, '*.json')
      end
    end
  end

  # The base class is no suite of its own: Inferno registers every suite class when its body
  # closes, so take it out again
  TestScriptSuite.remove_self_from_repository
end
