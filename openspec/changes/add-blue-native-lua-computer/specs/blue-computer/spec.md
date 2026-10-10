## Purpose

Provide a distinct blue physical computer with a trusted event-driven shell, unlocked alongside the existing VM computer and safe to use in the same saved world.

## ADDED Requirements

### Requirement: Distinct blue computer model
The system SHALL provide a separate blue physical computer entity, item and recipe with localized shell-only model identification. It SHALL retain the original model and use its footprint, power requirements and recipe costs as the initial defaults.

#### Scenario: Models can be distinguished
- **WHEN** a user views the inventory or places both computer models
- **THEN** the new item/body are visibly blue and identified as the shell-only model, while original artwork, names and prototype identities remain unchanged

### Requirement: Existing research unlock
The blue recipe SHALL be unlocked by the same computer research as the original physical computer, without an additional technology. Availability SHALL be reconciled for forces that researched it before installing the update.

#### Scenario: Fresh research unlocks both models
- **WHEN** a force completes the existing physical-computer research
- **THEN** both physical computer recipes become available

#### Scenario: Previously researched force receives the recipe
- **WHEN** the update loads a save whose force already researched physical computers
- **THEN** the force can craft the blue model without repeating research

### Requirement: Additive backend selection
New blue computers SHALL use only the direct event-driven shell backend. Existing physical/personal computers and saved records without backend metadata SHALL retain VM execution. Unknown backends or incompatible experimental native states SHALL fail visibly with recoverable data intact, without executing another backend.

#### Scenario: Mixed-model saved world
- **WHEN** a VM editor is suspended beside a blue shell with partial command input or a pending file job and the game reloads or is configured
- **THEN** the VM resumes unchanged and the shell retains its own session/job without conversion, startup replay or duplicate effects

#### Scenario: Unsupported backend or experimental state
- **WHEN** a computer has an unknown backend or a retained experimental continuation state that the shell cannot support
- **THEN** it reports a recovery error and preserves files/session/staging or original experimental data instead of booting another backend or reinterpreting it as shell state

### Requirement: Authorized model-independent interaction
Blue computers SHALL retain existing physical-terminal force, surface, range, research and GUI ownership checks. Closing a terminal SHALL not stop powered jobs. Power loss SHALL pause shell/job progress, with deterministic documented timer behavior and no automatic reboot when power returns.

#### Scenario: Unauthorized input is rejected
- **WHEN** an unauthorized player attempts to open or send input to a blue computer
- **THEN** no shell event is accepted and that request changes no disk/session/job state

#### Scenario: Powered session continues after closing
- **WHEN** an authorized user closes the terminal while a bounded shell job is pending
- **THEN** the powered computer continues admitted processing and a later reopen shows the current session rather than a fresh prompt session

#### Scenario: Power returns during a job
- **WHEN** a blue computer loses power during a pending command and later regains power
- **THEN** retained progress continues under the documented timer/work policy without reboot, renewed same-tick credits or duplicate committed effects

### Requirement: Model-aware lifecycle and snapshots
Build, discovery, clone, blueprint and removal SHALL recognize both models. Copies SHALL receive fresh identity and validated committed disk content, never live session/jobs/timers/staged changes. Removal SHALL clean only the removed computer's runtime and owned resources.

#### Scenario: Clone and blueprint a blue shell
- **WHEN** a blue computer with committed files, partial input and a pending job is cloned or rebuilt from its blueprint
- **THEN** the result retains the blue model/files and fresh identity but boots a fresh shell without copying the source's command buffer, job, timers or staged changes

#### Scenario: Rejected snapshot payload
- **WHEN** a snapshot contains invalid paths, node types, quota-exceeding content or executable/job payloads outside the committed disk contract
- **THEN** validation rejects it without partial disk installation or executable host values

#### Scenario: Remove one model beside the other
- **WHEN** a blue computer is mined or destroyed beside an active original computer
- **THEN** only the removed computer's scheduling and owned resources are cleaned up

### Requirement: Initialization-aware lifecycle and readback
A blue computer with no validated installed disk SHALL report initializing and SHALL refuse file snapshot, clone and blueprint export as not-ready rather than exposing unvalidated input, empty replacement content or partial import staging. Where a previous committed disk exists, readback SHALL expose only that disk until atomic replacement. New copies SHALL initialize from committed content with fresh identity/import progress, never a source's live import job. Power loss and viewer closure SHALL not reset retained import; invalid or incompatible initialization SHALL preserve safe recovery data instead of silently installing an empty disk.

#### Scenario: Inspect or copy unfinished initialization
- **WHEN** a trusted caller requests files, clone or blueprint export before first import publication
- **THEN** status identifies initialization and export reports not-ready without leaking staging or treating it as committed content

#### Scenario: Atomic import readback transition
- **WHEN** an import publishes its complete validated disk under admitted work
- **THEN** readback switches atomically from the previous committed disk or not-ready status to the complete installed disk, and later copies receive only that committed content

### Requirement: Backend-aware trusted metadata
Trusted inspection SHALL report model/backend/running status accurately while preserving existing metadata fields. File snapshots SHALL read each backend's current authoritative committed local disk and SHALL NOT expose host executables or unpublished job staging.

#### Scenario: Inspect after filesystem publication
- **WHEN** a shell command moves/deletes files and a trusted caller inspects or snapshots the computer before reboot
- **THEN** metadata identifies the event-shell model and the snapshot reflects the current committed disk rather than a stale boot-time alias or unpublished changes
