# Spec Delta

## Purpose

Allow bounded blue-computer scripts to control production through their own circuit ports, with a complete editable factory example and no unrestricted Factorio-object access.

## ADDED Requirements

### Requirement: Owned blue circuit ports
Blue physical computers SHALL expose two owned circuit ports using the existing positioned port prototype. Port lifecycle MUST preserve original/personal computer behavior, player wiring and unrelated entities. It MUST create/repair only missing owned resources and safely clear/destroy them on removal or ownership invalidation.

#### Scenario: Place and reconnect a blue controller
- **WHEN** a blue computer is placed, cold-loaded or reconfigured with circuit connections
- **THEN** its left/right port identities and player wires are retained or safely reconciled, with no legacy speaker/lamp bundle or mutations to original prototypes

### Requirement: Authorized scalar circuit access
`circuit.read(side,wire,type,name)` SHALL return one normal-quality signal count, zero for an unconnected valid port. `circuit.write(side,type,name,count)` and `circuit.clear(side)` SHALL stage only owned outputs. Services MUST validate side, wire, prototype, finite int32 count, body/port ownership, force, surface, research, power and program generation, and return no engine objects.

#### Scenario: Restricted production control
- **WHEN** an authorized powered controller reads an item signal from its left red network and writes a virtual enable signal on its right port
- **THEN** it receives a scalar count and only its own validated output section changes after successful callback publication

#### Scenario: Invalid or unauthorized access
- **WHEN** a script supplies malformed identity/count data or accesses a missing, stolen, wrong-force/surface or unpowered port
- **THEN** the operation fails visibly, never scans arbitrary world entities and never changes unrelated ports or player combinator sections

### Requirement: Bounded private output banks
Each side SHALL retain at most 32 output identities and callbacks SHALL permit at most 16 circuit calls. Zero counts MUST remove an identity. All entries and admission MUST be validated before replacing the owned manual section; output cleanup MUST remain safe under ordinary script-credit exhaustion.

#### Scenario: Refuse overflow before publication
- **WHEN** a callback exceeds output-bank or circuit-call limits or has insufficient publication credits
- **THEN** it publishes no staged bank or state changes and bounded fail-safe cleanup remains available

### Requirement: Editable runnable stock-control example
The package SHALL include read-only stock-controller example data, copy/edit/save/run instructions, signal/quality limits and wiring guidance. The example MUST read a chest's item stock through a separate left input network and emit a right production-enable signal for a circuit-controlled inserter using the actual edited threshold.

#### Scenario: End-to-end edited automation
- **WHEN** a player copies the example locally, changes the threshold in edit, saves and runs it with a read-enabled chest and wired inserter
- **THEN** the actual edited source controls signal-A and inserter operation above/below the new threshold, without direct inventory/entity privileges or VM execution

#### Scenario: Stop, power failure and cold reload
- **WHEN** the example is stopped, loses power or is saved/reloaded between due events
- **THEN** outputs fail safe on stop/power failure, restoration re-evaluates stock once, and cold reload does not duplicate startup effects or replay a committed callback

### Requirement: Honest packaged and client acceptance
The exact package SHALL pass Factorio 2.0.77 base/expansion editor/compiler/circuit/persistence/security/neighbor fixtures while preserving pinned vendor and original VM ROM bytes. Native graphical editing/wiring and a real multiplayer join during dirty editing and pending controller work MUST be verified separately before claiming complete acceptance.

#### Scenario: Unavailable client evidence
- **WHEN** only headless engine and structural GUI fixtures are available
- **THEN** those results are labeled precisely and graphical/multiplayer requirements remain explicitly blocked, not checked as complete or implied by packaging success
