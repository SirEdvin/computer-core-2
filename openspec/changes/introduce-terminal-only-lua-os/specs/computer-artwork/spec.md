## Purpose

Optionally present the Refreshed Advanced Computer appearance in Factorio using independently cleared assets without compromising terminal delivery.

## ADDED Requirements

### Requirement: Cleared asset distribution
Every redistributed source or derived artwork asset SHALL have recorded provenance, revision/hash, an applicable redistribution license or explicit permission, and required attribution. A pack-wide license SHALL not override incompatible borrowed-asset terms.

#### Scenario: Borrowed texture is not cleared
- **WHEN** a selected texture or model has unresolved provenance or incompatible terms
- **THEN** it and derived sprites containing it are excluded from the distributable package

### Requirement: Target appearance with fallback
The world-art target SHALL be ComputerCraft: Greg Flavored's Refreshed Advanced Computer. If the complete selected appearance cannot be cleared, the system SHALL retain existing computer artwork rather than block terminal rollout or silently select another pack variant.

#### Scenario: Screen overlay remains unresolved
- **WHEN** the casing is cleared but its required screen overlay is not
- **THEN** the shipped mod retains existing world artwork and records why replacement was deferred

### Requirement: Factorio-compatible sprite delivery
Cleared artwork SHALL be converted into packaged Factorio sprites/icons without requiring Minecraft, a native renderer or downloaded assets during gameplay. Replacement art SHALL not change the entity's existing gameplay footprint or behavior.

#### Scenario: Packaged mod renders computer
- **WHEN** the packaged mod is loaded in the Factorio client with cleared replacement art
- **THEN** the computer and icon render correctly at supported directions/states and retain their existing interaction footprint
