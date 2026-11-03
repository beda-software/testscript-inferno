RSpec.describe InfernoTemplate::TestScriptGroup do
  let(:suite_id) { 'au_core' }
  let(:ig_dir) { File.join(InfernoTemplate::TESTSCRIPT_DIR, 'au-core') }
  let(:suite) { Inferno::Repositories::TestSuites.new.find(suite_id) }
  let(:session_data_repo) { Inferno::Repositories::SessionData.new }
  let(:results_repo) { Inferno::Repositories::Results.new }
  let(:requests_repo) { Inferno::Repositories::Requests.new }
  let(:test_session) { repo_create(:test_session, test_suite_id: suite_id) }
  let(:validation_url) { "#{ENV.fetch('FHIR_RESOURCE_VALIDATOR_URL')}/validate" }

  let(:url) { 'http://example.com/fhir' }
  let(:authorization) { 'Basic cm9vdDpzZWNyZXQ=' }
  let(:json) { { 'Content-Type' => 'application/fhir+json' } }

  def run(runnable, inputs)
    test_run = Inferno::Repositories::TestRuns.new.create(
      { test_session_id: test_session.id }.merge(runnable.reference_hash)
    )
    inputs.each do |name, value|
      session_data_repo.save(test_session_id: test_session.id, name:, value:, type: 'text')
    end
    Inferno::TestRunner.new(test_session:, test_run:).run(runnable)
  end

  def resource(name)
    JSON.parse(File.read(File.join(ig_dir, "#{name}.json")))
  end

  def results(group)
    results_repo.current_results_for_test_session_and_runnables(test_session.id, group.tests)
      .to_h { |result| [result.runnable.title, result] }
  end

  def validator_outcome(issues = [])
    { outcomes: [{ issues: }], sessionId: test_session.id }.to_json
  end

  describe 'suites' do
    let(:suites) { InfernoTemplate::TestScriptSuite.subclasses }

    it 'has a suite per TestScript/<IG> directory, all listed in the test kit' do
      expect(suites.map(&:testscript_dir))
        .to match_array(Dir[File.join(InfernoTemplate::TESTSCRIPT_DIR, '*')].select { |path| File.directory?(path) })
      expect(InfernoTemplate::Metadata.suite_ids).to match_array(suites.map(&:id))
      expect(Inferno::Repositories::TestSuites.new.find(InfernoTemplate::TestScriptSuite.id)).to be_nil
    end

    it 'shares the inputs and FHIR client, and sets up the validator per suite' do
      expect(suite).to eq(InfernoTemplate::AuCoreSuite)
      expect(suite.inputs).to eq(%i[url authorization xml_support])
      expect(suite.fhir_client_definitions.keys).to eq([:default])
      expect(suite.fhir_validators[:default].map(&:igs)).to eq([['hl7.fhir.au.core#2.0.0']])
      expect(suite.fhir_validators[:default].first.validation_context.definition)
        .to include(txServer: 'https://tx.hl7.org.au/fhir')
      expect(InfernoTemplate::IeCoreSuite.fhir_validators[:default].first.validation_context.definition)
        .to_not have_key(:txServer)
      expect(suite.short_title).to eq('AU Core TestScript')
    end

    it 'has a local Aidbox preset, on the host and in Docker, for every suite' do
      presets = Dir[File.expand_path('../../config/presets/*.json', __dir__)].map { |path| JSON.parse(File.read(path)) }

      suites.each do |ig_suite|
        expect(presets.select { |preset| preset['test_suite_id'] == ig_suite.id }.map { |preset| preset['id'] })
          .to contain_exactly("#{ig_suite.id}_local_aidbox", "#{ig_suite.id}_local_aidbox_docker")
      end
    end

    InfernoTemplate::TestScriptSuite.subclasses.each do |ig_suite|
      it "defines a group per TestScript in #{ig_suite.id}, with Setup, its tests and Teardown" do
        scripts = Dir[File.join(ig_suite.testscript_dir, '*.json')]
          .map { |path| JSON.parse(File.read(path)) }
          .select { |definition| definition['resourceType'] == 'TestScript' }

        expect(ig_suite.groups.map(&:title)).to match_array(scripts.map { |script| script['title'] || script['name'] })

        scripts.each do |script|
          group = ig_suite.groups.find { |g| g.id == "#{ig_suite.id}-#{script['id'].tr('-', '_')}" }
          expect(group).to be_run_as_group
          tests = script.fetch('test', []).map.with_index(1) { |test, index| test['name'] || "Test #{index}" }
          expect(group.tests.map(&:title)).to eq(['Setup', *tests, 'Teardown'])
        end
      end
    end
  end

  describe 'fixtures referenced by a path from the IG directory' do
    let(:suite_id) { 'ch_elm' }
    let(:group) { suite.groups.find { |g| g.id.end_with?('-Test100_Kosovo') } }

    it 'loads them in Setup' do
      run(group.tests.first, url:)

      script = JSON.parse(File.read(File.join(suite.testscript_dir, 'Test100-Kosovo.json')))
      expect(script['fixture'].map { |fixture| fixture.dig('resource', 'reference') }).to all(start_with('/server/'))
      expect(results(group)['Setup'].then { |result| [result.result, result.result_message] }).to eq(['pass', nil])
    end
  end

  describe 'running the AU Core Patient group' do
    let(:group) { suite.groups.find { |g| g.id.end_with?('-au_core_patient') } }
    let(:patient) { resource('au-core-patient-conformant') }
    let(:patient_url) { "#{url}/Patient/#{patient['id']}" }
    let(:bundle) { { resourceType: 'Bundle', type: 'searchset', entry: [{ resource: patient }] } }

    before do
      stub_request(:put, patient_url).to_return(status: 201, body: patient.to_json, headers: json)
      stub_request(:get, patient_url).to_return(status: 200, body: patient.to_json, headers: json)
      stub_request(:get, "#{url}/Patient").with(query: hash_including({}))
        .to_return(status: 200, body: bundle.to_json, headers: json)
      stub_request(:delete, patient_url).to_return(status: 204)
      stub_request(:post, validation_url).to_return(status: 200, body: validator_outcome)
    end

    it 'passes every test and records its requests' do
      run(group, url:, authorization:)

      expect(results(group).transform_values { |result| [result.result, result.result_message] })
        .to all(satisfy { |_title, (result, _message)| result == 'pass' })
      expect(a_request(:get, patient_url).with(headers: { 'Authorization' => authorization }))
        .to have_been_made.times(3)
      expect(a_request(:delete, patient_url)).to have_been_made.once

      requests = results(group).transform_values { |result| requests_repo.requests_for_result(result.id) }
      expect(requests['Setup'].map(&:verb)).to eq(['put'])
      expect(requests['SearchById'].map(&:url)).to eq(["#{url}/Patient?_id=#{patient['id']}"])
      expect(requests['Teardown'].map(&:verb)).to eq(['delete'])
    end

    it 'fails only the test whose assert fails, and still deletes the fixtures' do
      other = patient.merge('name' => [{ 'family' => 'Smith' }])
      stub_request(:get, "#{url}/Patient").with(query: { '_id' => patient['id'] })
        .to_return(status: 200, body: bundle.merge(entry: [{ resource: other }]).to_json, headers: json)

      run(group, url:, authorization:)

      expect(results(group).reject { |_title, result| result.result == 'pass' }.transform_values(&:result))
        .to eq('SearchById' => 'fail')
      expect(results(group)['SearchById'].result_message)
        .to include("Check: Bundle.entry.resource.ofType(Patient).name.family.contains('Frog')")
      expect(a_request(:delete, patient_url)).to have_been_made.once
    end

    it 'fails profile validation with the validator messages' do
      stub_request(:post, validation_url).to_return(
        status: 200,
        body: validator_outcome([{ location: 'Patient.gender', message: 'bad gender', level: 'ERROR' }])
      )

      run(group, url:, authorization:)

      result = results(group)['ProfileValidation']
      expect(result.result).to eq('fail')
      expect(result.result_message).to include('au-core-patient')
      expect(result.messages.map(&:message)).to include(/bad gender/)
      expect(
        a_request(:post, validation_url).with do |request|
          JSON.parse(request.body).values_at('cliContext', 'validationContext').compact.first['txServer'] ==
            'https://tx.hl7.org.au/fhir'
        end
      ).to have_been_made.at_least_once
    end

    it 'fails Setup when the server rejects a fixture, and skips the tests' do
      stub_request(:put, patient_url).to_return(status: 500, body: 'boom')

      run(group, url:, authorization:)

      expect(results(group).transform_values(&:result))
        .to include('Setup' => 'fail', 'Read' => 'skip', 'Teardown' => 'pass')
    end
  end
end
