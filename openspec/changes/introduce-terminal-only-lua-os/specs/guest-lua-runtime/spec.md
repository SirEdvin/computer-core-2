## Purpose

Execute interactive Lua programs safely inside Factorio while preserving suspended execution across saves and multiplayer synchronization.

## ADDED Requirements

### Requirement: Guest execution and virtual coroutines
The system SHALL execute source-loaded Lua programs in an isolated guest environment with nested calls, closures, protected calls and virtual coroutine create/resume/yield/status behavior, preserving nil-containing return tuples and shared upvalues.

#### Scenario: Nested suspension preserves results
- **WHEN** a nested function yields inside a guest coroutine and is later resumed with multiple values including nil
- **THEN** the caller receives the correct ordered values, shared upvalues retain identity, and coroutine status reflects the resumed execution

#### Scenario: Protected guest failure
- **WHEN** guest code raises an error inside a protected call
- **THEN** the guest receives the protected-call failure without crashing Factorio or another computer

### Requirement: Durable suspended execution
The system SHALL preserve guest execution, terminal state, event queues, timers, local file-handle offsets and guest object identity across save/reload and multiplayer joining, without rebooting the OS or executing guest code during load callbacks.

#### Scenario: Save while editing
- **WHEN** the editor is waiting for input with unsaved text and the game is saved and reloaded in another engine process
- **THEN** editing resumes with the same buffer, cursor, coroutine state and open handles rather than restarting the editor

#### Scenario: Client joins suspended session
- **WHEN** a player joins while a guest program is waiting for an event
- **THEN** the player sees the existing terminal and subsequent execution remains synchronized with existing clients

### Requirement: Bounded execution and resources
The system SHALL enforce documented per-computer and aggregate execution budgets, allocation/content quotas, and bounded compilation, event admission and host operations. Budget exhaustion SHALL not freeze Factorio or corrupt saved files.

#### Scenario: Infinite loop cannot monopolize a tick
- **WHEN** one computer runs an infinite loop while another is waiting for user input
- **THEN** the looping program is preempted or fails recoverably within the configured bounds and the other computer continues receiving service

#### Scenario: Expensive helper is bounded
- **WHEN** a program requests oversized compilation, string work, queued events or file content
- **THEN** the request is rejected or performed within bounded work without bypassing execution limits

### Requirement: Guest sandbox boundary
The guest SHALL access only approved terminal/local-file services and safe language facilities. It SHALL NOT access Factorio objects, host globals, native IO, native code loading, other computers' disks or excluded world/network APIs.

#### Scenario: Attempted host escape
- **WHEN** guest code uses module loading, metatables, debug helpers or returned service values to attempt host access
- **THEN** it cannot obtain host functions or Factorio objects and receives an ordinary guest error for unsupported access

### Requirement: Blocking feasibility acceptance
The existing UI SHALL remain available until actual upstream shell/editor execution, bounded execution, separate-process save/reload, real client input/rendering and multiplayer joining have passed recorded acceptance checks.

#### Scenario: Compiler success is insufficient
- **WHEN** ROM sources compile but interactive execution or input capture has not passed acceptance
- **THEN** the workbench is not replaced and feasibility is reported as incomplete
