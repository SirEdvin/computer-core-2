# Client acceptance checklist (not yet executed)

Use Factorio 2.0.77 or newer, a fresh world and only the packaged mod (no test mod).
Repeat with base-only and the expansions you use. Do not report this checklist as
passed based on the playerless headless suite.

- Research Personal Computer and Computer; recipe appears; craft/place, connect power.
- Workbench tabs Terminal/Files/Waypoints/Help and active-tab marker are clear.
  Drag the titlebar, change tabs, and confirm window position is retained.
  Test 1280×720, 1920×1080 and your usual display at UI scales 1/1.5/2.
  Resize/change UI scale while editing; retain source/command/program-input drafts.
  Narrow forms stack and scroll; every action remains reachable without clipping.
- Terminal commands do not recreate/recenter the window; output updates live.
  Save/run/stop/folder creation and waypoint save/delete show immediate feedback;
  invalid commands and conflicting edits show explicit error text. Notices expire.
- Files: empty state, new file/folder, navigate parent, open/run file, shared mounts;
  stale/deleted entries fail safely. Run controls follow live process/power state.
- Program input: typing does not trigger a handler; Send or Enter sends once.
  No program/no power disables Send; a retained input draft is not overwritten by refresh.
- Ctrl+click the computer and each circuit connector. Confirm terminal opens with
  legible layout at your resolution/UI scale; commands work with Enter and Execute.
- Edit, Save, Save & run, Stop, clear, quoted file names and source-relative disk IO.
- Unsaved close/escape/navigation warning; concurrent edit conflict does not overwrite.
  Review the changed file and Keep draft & rebase; another intervening change
  must refresh the conflict rather than overwrite silently.
  Cut power while editing: keep the workbench/draft visible and show no-power status.
  Walk away, disconnect or destroy the computer while editing; use gauntlet
  Recover drafts and inspect `/recovered` for retained source.
- Ctrl+G and shortcut open personal computer after research with a character. Personal
  files remain private; no physical LAN/speaker APIs appear on the gauntlet.
  Move away from a surface that is then deleted; personal files/state must survive.
- Waypoint create/select/rename/delete, live coordinate camera preview, surface isolation.
- Attach red/green circuit wires to each foot: selection prioritizes the port, and
  wire endpoints/shadows align with the artwork (including existing wired computers
  after upgrading). Run circuit.lua. Verify outputs including item quality.
- `speaker.playNote`, named notes/instruments, volume and polyphony sound correct;
  alerts appear on map/force as intended, mute/stop remove them.
- Run receiver.lua and sender.lua on two computers; power-off pauses timers/messages,
  restored power resumes once; different force/surface cannot read mounts or messages.
- Blueprint an externally wired computer; robot-build/revive it and inspect wires and
  files. Clone/remove/undo/rebuild; no orphan connectors or duplicated process effects.
- Save while counter and receiver run, quit/reload, confirm state continues without init
  replay. Leave a draft open across save/reload and verify it can still be saved.
- With two real clients: join an active server while timers, libraries/extensions and
  terminal listeners run; verify no desync. Test both players editing one file, force
  changes/merge, respawn, surface change and reconnect. Check ownership/range gates.

Record Factorio version, enabled mods, UI scale and failed step when reporting issues.
