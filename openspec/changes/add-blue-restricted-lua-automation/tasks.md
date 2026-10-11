# Tasks

This follow-up explicitly supersedes only the predecessor's no-editor/no-user-program/no-circuit exclusions. Keep its original VM compatibility, shared caps, performance gates, historical experiment and incomplete client acceptance intact. These tasks are not completed by prior shell-only evidence. No publication, merge or archive is authorized here.

## 1. Native editor and committed writes

- [x] 1.1 Extend the admitted filesystem job path with atomic local file creation/replacement and base-content conflict detection; verify protected paths, missing parents, quotas, maximum accepted file/tree metadata, zero-credit inactivity, before/after-publication cold reload and unchanged unrelated files. Document overwrite/conflict behavior with those tests.
- [x] 1.2 Add a versioned native multiline editor and `edit PATH` routing in the blue shell; verify new/existing files, 32 KiB cap, newline insertion, middle paste/CRLF normalization, deletion, navigation, cursor/viewport and resize through the real terminal handler while poisoning VM/continuation entry points. Document exact controls and refused targets.
- [x] 1.3 Wire Ctrl+S/Ctrl+Q save/discard/cancel and dirty lifecycle disposition to the real save job and GUI; verify failures keep editable drafts, successful saves mark clean only after publication, cancel preserves the session, close/reopen retains state and native capture has no duplicate controls. Add the dirty-exit/save checklist to PLAYTEST.md.

## 2. Finite native source execution

- [x] 2.1 Reuse bounded Phobos analysis behind a new default-deny descriptor/handler validator; verify all documented scalar/local/conditional forms and refusal of loops, goto, arbitrary functions/globals, callable aliases, computed indexing, metatables, binary chunks and malformed descriptors with bounded line/column diagnostics. Document the complete supported grammar and source/state/AST limits.
- [x] 2.2 Emit and activate closed native handler wrappers from validated ASTs, not player text or saved generated code; verify literal escaping, scalar semantics, finite-result/string bounds, depth/node/emission caps, cold revalidation and warm/cold equal work admission with no VM, opcode/AST interpreter or continuation dispatch. Preserve original VM ROM/vendor bytes and document the trust boundary.
- [x] 2.3 Implement conservative whole-callback admission, bounded staged state/print records and validated publication; verify exact/one-short/zero-credit cases, bounded output FIFO that cannot overwrite an editor, false/nil scalar behavior and errors after staged mutations publish none of those changes. Document work mapping and expected-error versus unexpected-engine-fault behavior.
- [x] 2.4 Add committed-source `run PATH`, direct `.lua` invocation, background ownership, `ps` and `stop`; verify one active controller, stop-before-replace, source edits not changing a live snapshot, one-shot/periodic handlers, absolute deadlines and no on_start replay or catch-up storm. Document lifecycle and source-snapshot semantics.
- [x] 2.5 Gate expansion on an authentic editor-to-native-execution slice: create/edit/save/run a stateful printing controller, then benchmark cold boot and individual editor/shell echo beside the maximum allowed native callback using actual ticks in base/expansion. Verify unchanged caps and p95 two-tick terminal-model echo; retain failing attempts and halt expansion on failure rather than relaxing limits. Record sample counts and excluded graphical costs.

## 3. Owned circuit capabilities and useful factory example

- [x] 3.1 Extend blue lifecycle with exactly two owned left/right circuit ports, retaining original prototypes/VM behavior; verify real placement, owned registry identities, player wire preservation, repair, clone/revival, cold/configuration changes, force/surface changes and owned-only removal without the old speaker/lamp bundle. Document physical wiring and lifecycle boundaries.
- [x] 3.2 Implement scalar normal-quality circuit read/write/clear using pinned Factorio 2.0.77 contracts and staged output banks; verify real network counts, disconnected zero, missing-port errors, prototype/int32 validation, 32 outputs/side and 16 calls/callback, unauthorized/invalid ownership and no engine-object or alias leakage. Document the exact API, wire separation/feedback and quality limits.
- [x] 3.3 Reserve failure/power/stop cleanup from existing shared work before ordinary dispatch; verify exhausted same-tick credits, simultaneous transitions at the active-computer cap, pause/re-evaluation, errors during engine publication and no unrelated section/entity changes. Demonstrate original caps are neither renewed nor multiplied; document fail-safe outputs.
- [x] 3.4 Bundle the read-only stock-controller source and copy/edit/save/run instructions; run a deliberately edited threshold through the actual editor/compiler against a read-enabled chest and separately wired circuit-controlled inserter. Verify below/above-threshold signal-A, real inserter enable/transfer behavior, explicit stop, power failure/restoration and cold reload in base/expansion; validate resource manifests and document the reproducible factory layout.

## 4. Durable coexistence and adversarial acceptance

- [x] 4.1 Add admitted versioned editor/controller upgrade and recovery for 0.3.0 shell sessions; verify dirty drafts, queued print/save data, source/state/event/deadline/work identity, before/after-callback publication and zero-work on_load in separate processes, with warm/cold reconstruction parity and incompatible records retained inertly. Document upgrade/recovery and backup-only rollback.
- [x] 4.2 Exercise production backend/GUI/lifecycle routes beside suspended original/personal VM sessions; verify authorization, active opened-frame input, no resize focus theft, GUI close/reopen, dirty reboot/shutdown cancellation, direct selected routing and committed-file-only clones/blueprints without drafts, live controllers or outputs. Update client checklist and preserve legacy regressions.
- [x] 4.3 Add adversarial maximum source/state/print/API/output/save/queue fixtures and malformed saved records; verify no generated-text trust, no host code/object access, deterministic no-partial effects, cleanup under quota pressure and real interactive neighbors within unchanged shared limits. Record security/resource results independently of native-client claims.

## 5. Packaged integration and real-client gates

- [x] 5.1 Extend deterministic packaging/provenance checks for editor, compiler, runtime and bundled example data; run the exact ZIP's full Factorio 2.0.77 base/expansion editor-to-script-to-circuit matrix, old-save/configuration upgrades and separate-process persistence. Verify repeated ZIP bytes, original VM/vendor resources and Python/resource checks; record exact checksums and process outcomes without substituting source-symlink evidence.
- [ ] 5.2 Exercise a licensed graphical client editing/saving/running the stock example with visible blue ports and real factory wiring beside an original VM computer; verify focus/shortcuts/paste/resize, dirty-exit recovery and rendered responsiveness. Preserve screenshots/logs outside git and leave this task blocked if no client is available.
- [ ] 5.3 Exercise a real multiplayer join during dirty editing, exhausted script credits and a pending native controller event/save job; verify equal reconstructed source/state/draft/work, no on_load effects, exactly-once subsequent commits and preserved circuits/VM neighbor. Retain peer logs; headless/mock checks do not complete this gate.
- [x] 5.4 Consolidate scoped acceptance and limitations, rerun strict OpenSpec validation and prepare the follow-up implementation PR linked to the predecessor; verify every scenario is passed or explicitly blocking, with no incomplete checkbox marked done and no publication/merge/archive without separate authorization.

## Acceptance checkpoint

Headless/component evidence and local PR handoff are recorded in
`docs/BLUE_AUTOMATION_PR.md`. Tasks 5.2 and 5.3 remain blocked on a licensed
graphical client and a real joining peer, respectively. No full acceptance,
publication, merge or archive is claimed. The PR is prepared locally, not posted.
