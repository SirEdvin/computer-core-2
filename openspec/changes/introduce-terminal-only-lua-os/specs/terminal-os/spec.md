## Purpose

Deliver an upstream-owned Lua shell and editor with the terminal, event and local-file services needed for interactive use, without world compatibility APIs.

## ADDED Requirements

### Requirement: Upstream shell and editor
On first boot the computer SHALL present the selected upstream Lua shell and allow launching its upstream editor. Shell/editor behavior SHALL remain upstream-owned rather than being replaced by a mod-owned editor or native workbench.

#### Scenario: Edit and execute a local file
- **WHEN** a user boots the computer, launches the editor, creates a Lua file, saves it, reopens it and runs it from the shell
- **THEN** editing and shell behavior run in guest Lua and execution displays its output in the terminal

### Requirement: Terminal-only OS dependencies
The bundled OS SHALL include its terminal scheduler, helpers, local-file commands and required completion/settings modules. Peripheral, world, network and updater programs/services SHALL not be exposed or required for shell/editor startup.

#### Scenario: Completion without peripherals
- **WHEN** a user completes a local filename and opens the editor on a computer without world APIs
- **THEN** both operations succeed without requiring or simulating a peripheral service

### Requirement: Ordered events and timers
The guest SHALL provide ordered event queueing, filtered/raw event waits, termination handling, sleep and cancellable timers through the selected OS conventions and documented terminal-facing adapters. Time SHALL derive from synchronized simulation ticks.

#### Scenario: Timer resumes a waiting program
- **WHEN** a program starts a timer and waits for its timer event
- **THEN** the event carries the assigned timer ID after its simulation deadline and cancellation prevents an undelivered timer from firing

#### Scenario: Filtered wait and termination
- **WHEN** a program waits for a specific event and receives termination
- **THEN** the normal wait raises the documented termination error while raw waiting can receive termination as an event

### Requirement: Local disk and read-only ROM
The guest SHALL have a writable quota-limited local disk and read-only OS resources. File handles SHALL support the modes, reading, writing, seek/iteration and close behavior required by the selected editor. ROM loading SHALL not expose native or peer-computer files.

#### Scenario: ROM write rejected
- **WHEN** guest code attempts to replace an OS resource
- **THEN** the write fails without changing the bundled resource or another computer's files

#### Scenario: Quota failure retains saved content
- **WHEN** an editor save exceeds disk quota
- **THEN** the operation fails visibly and the previously saved file remains intact

### Requirement: Documented compatibility surface
The system SHALL document its selected OS module/event conventions, terminal API aliases, text encoding and unsupported APIs. It SHALL NOT advertise full CraftOS or general CC:Tweaked program compatibility.

#### Scenario: Unsupported module requested
- **WHEN** a program requests an excluded world or network API
- **THEN** the guest reports an unsupported or missing module instead of silently providing a fake successful implementation
