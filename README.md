# TestScript Test Kit

An [Inferno](https://github.com/inferno-community/inferno-core) Test Kit that runs the
[FHIR TestScripts](https://hl7.org/fhir/R4/testscript.html) of several IGs, one suite per IG in
`TestScript/<IG>/`, against a FHIR server. The scripts are executed by
[testscript_eval](https://github.com/beda-software/testscript-eval-ruby), which is included as a git submodule.

## Suites

| Suite id                   | Scripts from                                   | Against a local Aidbox (pass / fail)  |
|----------------------------|------------------------------------------------|----------------------------------------|
| `au_core`                  | AU Core 2.0.0 (validator: `tx.hl7.org.au`)     | 169 / 8                               |
| `at_core_r4`, `at_core_r5` | AT Core 2.1.0 (R4, R5)                         | 5 / 1 each                            |
| `ch_elm`                   | CH ELM 1.15.1                                  | 26 / 7                                |
| `fhir_emr`                 | [Beda EMR](https://github.com/beda-software/fhir-emr) (`81c7e77`), against its Aidbox | 45 / 0                  |
| `fhir_testing_ig`          | FHIR Testing IG                                | 72 / 9                                |
| `ie_core`                  | IE Core 0.2.0                                  | 10 / 1                                |
| `radiation_dose_summary`   | Radiation Dose Summary 1.0.0                   | 21 / 2                                |
| `us_directory_attestation` | US Directory Attestation 1.0.0-ballot          | 18 / 11 (6 skipped)                   |

The scripts and fixtures are third-party content. See [Sources and licenses](#sources-and-licenses)
for where each IG directory comes from and under what license.

No suite ends in an error against Aidbox. The fails are the server's answers, not engine problems:
operations Aidbox does not have (system-level `$validate`, XML, Subscription,
UDAP/OAuth endpoints), data the validator rejects (AU Core SNOMED display names, PBS code `2951H`),
Aidbox date search in UTC against `+10:00` times, and scripts that conflict with themselves or
with an earlier run (AT Core creates a Patient with a fixed id and never deletes it).

How results are reported:

- **pass**: every assert held; failed `warningOnly` asserts are warnings on the test.
- **fail**: an assert did not hold, or the server rejected a fixture (autocreate) or does not have one
  the script reads, or a response lacks a value a variable reads from it. The message names the
  assert and what it evaluated, e.g. ``Confirm that we have errors.: Expression `issue.where(severity='error').count()>0` on the response: Got false, expected "true"``.
- **error**: the script cannot run as written: an unsupported feature, a missing fixture file, a
  variable no one provided, or the validator could not be reached.
- **skip**: the group's Setup did not complete.

## How TestScripts map to Inferno

Every `TestScript/<IG>/` directory is an Inferno test suite (a short suite file in
`lib/inferno_template/suites/`), and every TestScript in it a test group; nothing is written by hand per script:

| Inferno                 | TestScript                                                                 |
|-------------------------|----------------------------------------------------------------------------|
| Suite                   | One `TestScript/<IG>/` directory, e.g. `TestScript/au-core/` is `au_core`  |
| Group                   | One TestScript (`title` or `name`, `description`)                         |
| **Setup** test          | Loads and autocreates `fixture`s, runs `setup`                             |
| One test per `test`     | The test's actions; a failed assert fails the test, `warningOnly` ones add warnings |
| **Teardown** test       | Runs `teardown` and autodeletes the fixtures, also after failures          |

- Variables are evaluated where they are used, so they can read the responses of setup and earlier
  test operations (`responseId`, `headerField`).
- A group always runs as a whole (`run_as_group`), as its tests share the fixtures created on the server.
  When Setup fails, the group's tests are skipped and Teardown still cleans up.
- Requests go through Inferno's FHIR client, so every request is listed on the test that made it.
- `validateProfileId` asserts use Inferno's FHIR resource validator, loaded with the IG packages the
  suite names (`igs:`) and checking codes against its terminology server (`tx_server:`, e.g.
  `https://tx.hl7.org.au/fhir` for AU Core; the validator's default, tx.fhir.org, otherwise); validation
  messages are shown on the test.
- Other resources in an IG directory (e.g. `au-core-patient-conformant.json`) are fixtures, referenced
  from the scripts by a path from the IG directory, as a `file://` URL or starting with `/`:
  `file://au-core-patient-conformant.json`, `/server/Patient-example.json`. Only the `*.json`, `*.yaml` and
  `*.yml` files directly in the IG directory are checked for TestScripts, so fixtures can also go in
  subdirectories. To add a script, drop a TestScript JSON or YAML file in its IG directory.
- A group's id is its TestScript's `id`, or the file name when the script has none or another script
  of the suite has the same one.
- `TestScript/<IG>/server/<Type>-<id>.json` hold the resources the upstream scripts expect on the
  server (`Type/id` fixture references, reads of fixed ids) and the resources those reference, taken
  unmodified from the IGs' packages. The scripts were rewired to them, see
  [Changes to the upstream TestScripts](#changes-to-the-upstream-testscripts).
- To add an IG, put its scripts and fixtures in `TestScript/<IG>/`, add a suite file in
  `lib/inferno_template/suites/` and the two Aidbox presets (see below):

  ```ruby
  # lib/inferno_template/suites/au_core_suite.rb
  module InfernoTemplate
    class AuCoreSuite < TestScriptSuite
      id :au_core
      title 'AU Core TestScript'
      # description '...'  # optional, defaults to a generic one

      testscripts 'au-core', igs: ['hl7.fhir.au.core#2.0.0'], tx_server: 'https://tx.hl7.org.au/fhir'
    end
  end
  ```

### TestScript support

The engine covers what these IGs' scripts use; see the
[testscript_eval README](testscript-eval-ruby/README.md#supported-features) for the full list. Beyond
basic read/search/create/update/delete:

- Fixtures from JSON, XML or YAML files (`file://`, `/path`, `../relative`), server references, and
  transaction Bundles; autocreate puts fixtures with ids in one transaction, so references between
  them resolve even in cycles.
- Every operation type (`updateCreate`, `validate`, `operation` with `$name`, `transaction`,
  `capabilities`, …), `url`, `requestHeader`, `accept`/`contentType`, Binary fixtures sent as their content.
- Variables from FHIRPath, JSONPath, XPath (`application/xml` expressions, `Bundle/entry/resource/Patient/id`
  paths) and response headers.
- Asserts on requests (`direction: request`, `requestURL`, `requestMethod`), on a `sourceId` response,
  every response code and operator, and R5 `common` actions and `profile`/`_profile`.

### Code

- `lib/inferno_template/test_script_group.rb`: `InfernoTemplate::TestScriptGroup`, the component
  that turns TestScript files into groups. Extend a suite or group with it and call
  `testscript_groups(glob)` (one group per TestScript among the matching files) or
  `testscript_group(definition, root_dir:)`.
- `lib/inferno_template/test_script_suite.rb`: `InfernoTemplate::TestScriptSuite`, the common base class of
  the suites, with the `url`, `authorization` and `xml_support` inputs and the FHIR client. Its
  `testscripts(dir, igs: [], tx_server: nil, validator_context: {})` macro sets up the validator (IG
  packages, terminology server, other validator settings such as `sv: '5.0.0'`) and a group per
  TestScript in `TestScript/<dir>/`. The base class itself is not listed as a suite.
- `lib/inferno_template/suites/*_suite.rb`: one suite per IG. `lib/inferno_template.rb` loads them all,
  and the test kit metadata lists every `TestScriptSuite` subclass.
- `testscript-eval-ruby/`: the testscript_eval submodule. The kit uses its step-by-step API
  (`Evaluator#start`, `#run_test`, `#finish`), and plugs in its own client
  (`TestscriptEval::Client.new(fhir_client, xml:) { |reply| ... }`) and validator.

## Inputs and presets

- **FHIR Server Base Url** (`url`)
- **Authorization header** (`authorization`, optional): sent as is, e.g. `Basic cm9vdDpzZWNyZXQ=`
- **Server supports FHIR XML** (`xml_support`, optional, default No): when a script asks for XML,
  send and accept XML. With No (e.g. Aidbox, which ignores XML bodies), JSON is used instead, and
  asserts that check for XML fail.
- TestScript variables the tester provides (no value, expression or path of their own, only a
  `hint`) are inputs of their group, named `testscript_<variable>`, e.g.
  `testscript_patient_search_family_name`.

Every suite has two presets in `config/presets/` for a local Aidbox with `root:secret`:

| Preset                             | Id                               | Use when Inferno runs         | Base URL                                |
|------------------------------------|----------------------------------|-------------------------------|-----------------------------------------|
| Local Aidbox                       | `<suite id>_local_aidbox`        | on the host (`inferno start`) | `http://localhost:8080/fhir`            |
| Local Aidbox (Inferno in Docker)   | `<suite id>_local_aidbox_docker` | in Docker (`./run.sh`)        | `http://host.docker.internal:8080/fhir` |

Inside Docker, `localhost` is the container itself, and `http://host.docker.internal/fhir` (no port)
reaches this kit's own nginx on port 80, which answers every request with 404. Keep the port of your
FHIR server in the URL. Inferno keeps a session's inputs, so after changing servers, update the URL in
the run dialog or start a new session from the preset.

## The validator

Every suite has its own validator session, and each session holds its own copy of the FHIR packages
(about 0.5 GB), so with all suites the validator needs several GB:

- `.env` sets `INITIALIZE_VALIDATOR_SESSIONS=false`: a session starts with its suite's first
  validation, not all of them at boot.
- `docker-compose.background.yml` expires sessions unused for 2 minutes (`SESSION_CACHE_DURATION`),
  so a run of all suites keeps only one or two in memory; a suite's first validation after a pause
  takes 10–40 s while its session loads again.
- It also caps the validator's heap at 4 GB (`JAVA_TOOL_OPTIONS: -Xmx4g`), so the JVM collects expired
  sessions instead of growing until Docker kills it. Give Docker at least 8 GB.
- When the validator runs out of memory anyway, Docker kills it (exit 137) and validations error with
  "Unable to connect to validator"; restart it with `docker compose up -d hl7_validator_service`.
- "Unable to connect to validator" also hides validator errors, e.g. a profile none of the suite's IG
  packages has (`Unable to resolve profile`); the validator log (`docker compose logs hl7_validator_service`)
  has the cause.

`lib/inferno_template/igs/` holds the AT Core 2.1.0 CI builds (`hl7.at.fhir.core.r4`/`.r5`), as the
published 2.0.0 packages lack the profiles the AT Core scripts validate against. The AT Core R5
suite runs the validator as FHIR R5 (`validator_context: { sv: '5.0.0' }`).

## Changes to the upstream TestScripts

The scripts come from the IGs as they are, except for these changes, made so they run against a
server that starts empty:

- Fixtures referencing a resource on the server (`Patient/example`) point to its file in `server/`
  (`/server/Patient-example.json`). They are `autocreate`/`autodelete` when the script reads them from
  the server (a `targetId`, a read of a fixed id) rather than only sending them.
- Scripts that read a fixed id without a fixture got one (e.g. IE Core `Encounter/ie-core-encounter-example`,
  FHIR Testing IG `Patient/example`, `Patient/f001`; `Patient/f002`, which no IG has, is a copy of `f001`).
- Resources the fixtures reference are autocreate fixtures too, as servers that check references
  (Aidbox) reject them otherwise. The engine creates them in one transaction, which also resolves
  reference cycles (FHIR core `Patient/pat1` and `pat2`, US Directory `Location` and `PractitionerRole`).
- Radiation Dose Summary: the RDS transaction Bundle is an autocreate fixture (the engine posts it to
  the server root and deletes what it created); `RDSC-Simulator`'s `rdsResourceId` is read from its response.
- FHIR Testing IG `testscript-example.json`: its fixtures have no reference upstream; they point to
  `Patient/example`, as in FHIR core's `testscript-example.json`.
- US Directory Attestation (Postman exports): `{{hostname}}/baseR4/` URLs are relative to the base URL,
  PUTs without a body send the fixture with the same `Type/id`, and fixtures without a resource are
  not autocreated.
- FHIR EMR: see [The FHIR EMR suite](#the-fhir-emr-suite).

### The FHIR EMR suite

`TestScript/fhir-emr/` holds the TestScripts of [Beda EMR](https://github.com/beda-software/fhir-emr)
(`resources/tests` at commit `81c7e77`). They test a fhir-emr deployment: its SDC `$populate`/`$extract`
on Aidbox (`http://localhost:8080/fhir`), and its seed Questionnaires and `Patient/patient1`, which the
scripts read from the server and which are not fixtures here, as autodelete would remove them.

- The directory is flat, like the other IGs: the scripts and their fixtures sit side by side, the
  scripts reference fixtures as `file://<name>.yaml`, and a fixture's `!include` resolves next to it.
  Upstream keeps them in `resources/tests/TestScript/` and `resources/tests/resources/`.
- The YAML scripts are upstream's. The JSON scripts were converted once from upstream's FSH with
  [kaitenzushi](https://github.com/beda-software/kaitenzushi), using the RuleSets and aliases of
  [beda-emr-core-zen](https://github.com/beda-software/beda-emr-core-zen), and are edited as JSON from
  then on.
- Upstream, the scripts ran against Aidbox's native API, so they were changed for the FHIR API:
  expressions on choice types and references (`answer.value.string` → `answer.value.ofType(string)`,
  `item.CodeableConcept` → `item.ofType(CodeableConcept)`, `subject.id` → `subject.reference`), Aidbox
  first-class extensions (HealthcareService `duration`, ChargeItemDefinition `healthcareService`) as FHIR
  extensions in the fixtures and expressions, `medication-request-3.yaml` in FHIR format, and the vitals
  teardown, which used an AidboxQuery, deletes the observations with a FHIR conditional delete.
- `medication-3.yaml` and `medication-request-confirm.yaml` are symlinks upstream whose targets moved;
  they are the seeds they pointed to (`resources/demo-seeds`, `resources/init-seeds` at `81c7e77`).
- `complete-encounter-questionnaire-response.yaml`: its start date was after its end date (Aidbox rejects
  the extracted Encounter); it is the encounter's start, as `$populate` gives.
- The cancel/confirm script cancels and confirms the seed `MedicationRequest/medication-request-3`: it
  autocreates it and `Medication/medication-3` in their seed state first, so it can run again.
- Creatinine leaves its extracted Observation on the server upstream; its teardown deletes it.
- Vitals is updated for the current fhir-emr (`27e1009d`, 2026-10-20), where the vitals Questionnaire
  nests its items in a `vitals-data` group and asks for quantities (`81c7e77` had decimals):
  `vitals-questionnaire.yaml` is that Questionnaire as fhir-emr serves it, the QuestionnaireResponse
  answers with `valueQuantity` in each item's unit, and the script compares the quantities' values. The
  second blood pressure check, a copy of the systolic one upstream, checks the diastolic value (8462-4).

## Getting Started

The quickest way to run this test kit locally is with [Docker](https://www.docker.com/).

- Install Docker
- Clone this repository with its submodule:
  `git clone --recurse-submodules <repo>`, or run `git submodule update --init` in an existing clone
- Run `./setup.sh` within the test kit directory to download necessary dependencies
- Run `./run.sh` within the test kit directory to start the application
- Navigate to `http://localhost`, create a session for one of the suites (e.g. `AU Core TestScript`) and pick a preset.
  The scripts create their fixtures on the server and delete them again, so an empty server works.

From the command line, with the background services running (`bundle exec inferno services start`):

```sh
bundle exec inferno migrate
bundle exec inferno execute --suite au_core --preset-id au_core_local_aidbox
```

Presets in `config/presets/` are loaded automatically: select them with `--preset-id`, not `--preset-file`.

## Developing

Refer to the Inferno documentation for information about [setting up
your development environment and running your Test Kit](https://inferno-framework.github.io/docs/getting-started/).

### Reloading on changes

Run Inferno on the host with the background services in Docker, and it restarts whenever the kit,
a TestScript or a fixture changes:

```sh
bundle exec inferno services start   # validator, FHIRPath, nginx, redis
bundle exec inferno start --watch     # http://localhost:4567
```

`bundle install` installs foreman and rerun, which `inferno start` uses. `.rerun` sets what is
watched: `lib/`, `TestScript/`, `testscript-eval-ruby/lib/` and `config/`, for `.rb`, `.ru`, `.json`,
`.yaml`/`.yml`, `.xml`, `.fsh` and `.tgz` files. rerun's defaults skip `.json` and `.yaml`, so
TestScripts were not reloaded. `data/` is not watched, as Inferno writes its database there.

In Docker (`./run.sh`), `docker-compose.override.yml`, which docker compose merges into
`docker-compose.yml`, does the same: it mounts the kit into the `inferno` and `worker` containers
instead of the copy in the image, and runs both under rerun with the same `.rerun`, polling for
changes, as file events from the host do not always reach the container. A change shows up at
`http://localhost` a few seconds later. Changes to `Gemfile` or `Gemfile.lock` still need a rebuild
(`./run.sh`, or `docker compose up -d --build inferno worker`). To run the image as built, without
reloading: `docker compose -f docker-compose.yml up`.

### The testscript_eval submodule

The `testscript_eval` gem is loaded from the `testscript-eval-ruby/` submodule
(`gem 'testscript_eval', path: 'testscript-eval-ruby'`), which the Dockerfile copies into the image
before `bundle install`. The CI workflows check out submodules.

- To work on testscript_eval, commit and push in `testscript-eval-ruby/`, then commit the new submodule
  pointer here. Docker and CI clone the pinned commit from GitHub, so it has to be pushed.
- To update it: `git -C testscript-eval-ruby pull`, then commit the submodule pointer.
- `.gitmodules` uses HTTPS so CI and Docker can clone without SSH keys. To push over SSH locally:

  ```sh
  git config submodule.testscript-eval-ruby.url git@github.com:beda-software/testscript-eval-ruby.git
  git -C testscript-eval-ruby remote set-url origin git@github.com:beda-software/testscript-eval-ruby.git
  ```

  `git submodule sync` resets the URL to the HTTPS one from `.gitmodules`.

### Verifying test kit logic

- Unit tests (rspec) in `spec/`: `bundle exec rspec`. `spec/inferno_template/test_script_group_spec.rb`
  checks that every IG directory has a suite with presets and every TestScript becomes a group, runs the
  AU Core Patient group against stubbed requests, and loads the CH ELM `/server/` fixtures.
  testscript_eval has its own specs (`spec/features_spec.rb` covers the TestScript features above):
  `cd testscript-eval-ruby && bundle exec rspec`.
- Against a real server, run every suite and compare with the table in [Suites](#suites):

  ```sh
  for suite in au_core at_core_r4 at_core_r5 ch_elm fhir_emr fhir_testing_ig ie_core \
               radiation_dose_summary us_directory_attestation; do
    bundle exec inferno execute --suite $suite --preset-id ${suite}_local_aidbox
  done
  ```
- Lint: `bundle exec rubocop` (the submodule is excluded).
- Both run in the ruby.yml workflow (`.github/workflows/ruby.yml`).
- Execution scripts: none are included; the template's demo script was removed. See
  [CI/CD Usage](https://inferno-framework.github.io/docs/ci-cd-usage.html) for adding them to
  `execution_scripts/`, where the run_inferno_execution_scripts.yml workflow picks them up.

## Documentation
- [Inferno documentation](https://inferno-framework.github.io/docs/)
- [Ruby API documentation](https://inferno-framework.github.io/inferno-core/docs/)
- [JSON API documentation](https://inferno-framework.github.io/inferno-core/api-docs/)
- [testscript_eval](https://github.com/beda-software/testscript-eval-ruby)

## Sources and licenses

The TestScripts and fixtures in `TestScript/` are not part of this kit's own code: they were taken
from the IGs below and remain under their publishers' licenses. They are changed only as described in
[Changes to the upstream TestScripts](#changes-to-the-upstream-testscripts). Their publishers have not
reviewed or endorsed this kit, and the scripts are included as test data only.

| Directory | Source | Publisher | License |
|-----------|--------|-----------|---------|
| `au-core` | [AU Core tests](https://github.com/jgsuess/au-core-tests) (`fhirfrog.au-core-tests` 0.1.0, [CI build](https://build.fhir.org/ig/jgsuess/au-core-tests/)) | FHIR Frog | [Apache-2.0](https://github.com/jgsuess/au-core-tests/blob/main/LICENSE) (repository); the package declares CC0-1.0 |
| `at-core-r4` | [HL7 AT Core R4](https://build.fhir.org/ig/HL7Austria/HL7-AT-FHIR-Core-R4/) (`hl7.at.fhir.core.r4` 2.1.0 CI build) | HL7® Austria, TC FHIR® | [CC0-1.0](https://creativecommons.org/publicdomain/zero/1.0/) |
| `at-core-r5` | [HL7 AT Core R5](https://build.fhir.org/ig/HL7Austria/HL7-AT-FHIR-Core-R5/) (`hl7.at.fhir.core.r5` 2.1.0 CI build) | HL7® Austria, TC FHIR® | [CC0-1.0](https://creativecommons.org/publicdomain/zero/1.0/) |
| `ch-elm` | [CH ELM](https://fhir.ch/ig/ch-elm/1.15.1/) (`ch.fhir.ig.ch-elm` 1.15.1) | Federal Office of Public Health FOPH | [CC0-1.0](https://creativecommons.org/publicdomain/zero/1.0/) |
| `fhir-testing-ig` | [FHIR Testing IG](https://hl7.org/fhir/uv/testing/0.1.0-snapshot1/) (`hl7.fhir.uv.testing` 0.1.0-snapshot1); `server/` resources from the [FHIR R4 examples](https://hl7.org/fhir/R4/downloads.html) | HL7 International / FHIR Infrastructure | [CC0-1.0](https://creativecommons.org/publicdomain/zero/1.0/) ([FHIR license](https://hl7.org/fhir/R4/license.html)) |
| `ie-core` | [IE Core](https://hl7-ie.github.io/ie-core/) (`nostalgic-ie.fhir.core` 0.2.0) | Nithin Mohan T K | [CC-BY-4.0](https://creativecommons.org/licenses/by/4.0/), see the credit below |
| `radiation-dose-summary` | [Radiation Dose Summary for Diagnostic Procedures](https://hl7.org/fhir/uv/radiation-dose-summary/) (`hl7.fhir.uv.radiation-dose-summary` 1.0.0) | HL7 International / Imaging Integration | [CC0-1.0](https://creativecommons.org/publicdomain/zero/1.0/) |
| `fhir-emr` | [Beda EMR](https://github.com/beda-software/fhir-emr) (`resources/tests` at `81c7e77`); FSH RuleSets from [beda-emr-core-zen](https://github.com/beda-software/beda-emr-core-zen) | Beda Software | [MIT](https://github.com/beda-software/fhir-emr/blob/main/LICENSE) |
| `us-directory-attestation` | [National Directory of Healthcare Providers & Services – Attestation](https://hl7.org/fhir/us/directory-attestation/2022Sep/) (`hl7.fhir.us.directory-attestation` 1.0.0-ballot) | HL7 Patient Administration Working Group | [CC0-1.0](https://creativecommons.org/publicdomain/zero/1.0/) |

The packages are available from the [FHIR package registry](https://packages.fhir.org/), or from the CI
build linked above where noted.

**Credit for `ie-core`:** the TestScripts and example resources in `TestScript/ie-core/` are from
[IE Core](https://hl7-ie.github.io/ie-core/) (`nostalgic-ie.fhir.core` 0.2.0), a proof of concept by
Nithin Mohan T K, licensed under [CC BY 4.0](https://creativecommons.org/licenses/by/4.0/). They were
modified for this kit, as described in
[Changes to the upstream TestScripts](#changes-to-the-upstream-testscripts): the scripts' fixture
references now point to the files in `server/`, and fixtures were added for reads of fixed ids.

## License
Copyright 2026 TODO

Licensed under the Apache License, Version 2.0 (the "License"); you may not use
this file except in compliance with the License. You may obtain a copy of the
License at
```
http://www.apache.org/licenses/LICENSE-2.0
```
Unless required by applicable law or agreed to in writing, software distributed
under the License is distributed on an "AS IS" BASIS, WITHOUT WARRANTIES OR
CONDITIONS OF ANY KIND, either express or implied. See the License for the
specific language governing permissions and limitations under the License.

## Trademark Notice

HL7, FHIR and the FHIR [FLAME DESIGN] are the registered trademarks of Health
Level Seven International and their use does not constitute endorsement by HL7.
