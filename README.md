# AU Core TestScript Test Kit

An [Inferno](https://github.com/inferno-community/inferno-core) Test Kit that runs
[FHIR TestScripts](https://hl7.org/fhir/R4/testscript.html) from `TestScript/<IG>/` against a FHIR server.
The scripts are executed by [testscript_eval](https://github.com/beda-software/testscript-eval-ruby),
which is included as a git submodule.

## How TestScripts map to Inferno

Every `TestScript/<IG>/` directory becomes an Inferno test suite, and every TestScript in it a test group;
nothing is written by hand per IG or per script:

| Inferno                 | TestScript                                                                 |
|-------------------------|----------------------------------------------------------------------------|
| Suite                   | One `TestScript/<IG>/` directory, e.g. `TestScript/au-core/` is `au_core`  |
| Group                   | One TestScript (`title` or `name`, `description`)                         |
| **Setup** test          | Loads and autocreates `fixture`s, resolves `variable`s, runs `setup`        |
| One test per `test`     | The test's actions; a failed assert fails the test, `warningOnly` ones add warnings |
| **Teardown** test       | Runs `teardown` and autodeletes the fixtures, also after failures          |

- A group always runs as a whole (`run_as_group`), as its tests share the fixtures created on the server.
  When Setup fails, the group's tests are skipped and Teardown still cleans up.
- Requests go through Inferno's FHIR client, so every request is listed on the test that made it.
- `validateProfileId` asserts use Inferno's FHIR resource validator, loaded with the IG packages the
  suite names (`igs:`) and checking codes against its terminology server (`tx_server:`, e.g.
  `https://tx.hl7.org.au/fhir` for AU Core; the validator's default, tx.fhir.org, otherwise); validation
  messages are shown on the test.
- Other resources in an IG directory (e.g. `au-core-patient-conformant.json`) are fixtures, referenced
  from the scripts by a path from the IG directory, as a `file://` URL or starting with `/`:
  `file://au-core-patient-conformant.json`, `/examples/Example_Request_001.json`. Only `*.json` files directly
  in the IG directory are checked for TestScripts, so fixtures can also go in subdirectories. To add a script, drop a TestScript JSON file in its IG directory.
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

### Code

- `lib/inferno_template/test_script_group.rb`: `InfernoTemplate::TestScriptGroup`, the component
  that turns TestScript files into groups. Extend a suite or group with it and call
  `testscript_groups(glob)` (one group per TestScript among the matching files) or
  `testscript_group(definition, root_dir:)`.
- `lib/inferno_template/test_script_suite.rb`: `InfernoTemplate::TestScriptSuite`, the common base class of
  the suites, with the `url` and `authorization` inputs and the FHIR client. Its `testscripts(dir, igs:)`
  macro sets up the validator and a group per TestScript in `TestScript/<dir>/`. The base class itself is
  not listed as a suite.
- `lib/inferno_template/suites/*_suite.rb`: one suite per IG. `lib/inferno_template.rb` loads them all,
  and the test kit metadata lists every `TestScriptSuite` subclass.
- `testscript-eval-ruby/`: the testscript_eval submodule. The kit uses its step-by-step API
  (`Evaluator#start`, `#run_test`, `#finish`), and plugs in its own client
  (`TestscriptEval::Client.new(fhir_client) { |reply| ... }`) and validator.

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
- `docker-compose.background.yml` expires sessions unused for 5 minutes (`SESSION_CACHE_DURATION`).
- Give Docker at least 8 GB. When the validator runs out of memory, Docker kills it (exit 137) and
  validations fail with "Unable to connect to validator"; restart it with
  `docker compose up -d hl7_validator_service`.

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

## Getting Started

The quickest way to run this test kit locally is with [Docker](https://www.docker.com/).

- Install Docker
- Clone this repository with its submodule:
  `git clone --recurse-submodules <repo>`, or run `git submodule update --init` in an existing clone
- Run `./setup.sh` within the test kit directory to download necessary dependencies
- Run `./run.sh` within the test kit directory to start the application
- Navigate to `http://localhost`, create a session for one of the suites (e.g. `AU Core TestScript`) and pick a preset

From the command line, with the background services running (`bundle exec inferno services start`):

```sh
bundle exec inferno migrate
bundle exec inferno execute --suite au_core --preset-id au_core_local_aidbox
```

Presets in `config/presets/` are loaded automatically: select them with `--preset-id`, not `--preset-file`.

## Developing

Refer to the Inferno documentation for information about [setting up
your development environment and running your Test Kit](https://inferno-framework.github.io/docs/getting-started/).

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
  checks that every IG directory has a suite with presets and every TestScript becomes a group, and runs the AU Core Patient group against stubbed requests.
  testscript_eval has its own specs: `cd testscript-eval-ruby && bundle exec rspec`.
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
