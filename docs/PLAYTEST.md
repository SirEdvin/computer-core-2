# 0.3.0 alpha playtest

Experimental terminal-OS playtest guidance for the **0.3.0 alpha** build;
not a publication announcement or stable acceptance claim. Graphical/client tests
below belong to the playtester and are **not yet passed**. See
[known limitations](KNOWN_LIMITATIONS.md) before upgrading.

## Install safely

1. **Back up your saves and keep an untouched copy.** Prefer a fresh test world;
   upgrade only a separate copy of an existing Computer Core 2 save.
2. Use Factorio **2.0.77 or newer**. Copy the supplied
   `computer_core_2_0.3.0.zip` into Factorio's `mods` directory and enable Computer
   Core 2. Do not enable the original `computer_core` alongside it. Ensure all
   multiplayer clients have the same mod version and startup settings.
3. Verify the archive/version supplied by the maintainer; this document does not
   establish that the ZIP has been built or published. For a source build, the
   repository packaging command is `python3 tools/package.py`.
4. **Do not downgrade a migrated save.** To return to 0.1.x, restore the untouched
   backup with its matching mod version, not the newly saved upgraded world.
5. Updating from 0.2.0/0.2.1: save all important files, then reboot each computer once.
   Existing guests retain their compiled OS modules until reboot. The upgrade
   does not automatically discard editor drafts; Reboot does discard unsaved buffers.

## Open a computer

- Research Personal Computer (`computer-gauntlet-technology`), then Computer
  (`computer-technology`) for the physical computer recipe.
- With a character and personal-computer research, **Ctrl + G** opens the personal
  gauntlet. Its session is private to its owner.
- Craft/place a physical computer, supply electricity, stay within 10 tiles and
  **Ctrl + left-click** its body. Physical hardware keeps the existing artwork;
  its ports/speaker do not imply guest API support.
- Physical computers use **50 kW**, with a **5 MJ** buffer and **300 kW** maximum
  input. Guest execution pauses when power is unavailable; do not mistake that
  for a failed boot. Personal computers require the character/research conditions,
  not a physical electricity connection.
- Consult **in-game controls** for terminal input capture and supported keys;
  do not assume every raw OS key or text encoding is supported.

Click the terminal itself to type or paste; accepted text is sent immediately.
The native capture widget is visually hidden but remains focusable. Press Enter to submit. Navigation uses
keyboard shortcuts; the fallback button row has been removed. Use **Ctrl+M**,
then type **s** to save or **e** to exit the advanced editor.
Clicking a terminal cell sends its one-based position; drag/physical release are
not implemented. Close preserves execution. Reboot discards unsaved guest buffers
but keeps saved files; Shutdown pauses the computer until Reboot. This is an
unverified client interface, not a guarantee of shortcut/focus compatibility.

## Shell → editor → source program

These commands are verified against the locally vendored Recrafted sources,
not inferred from the retired workbench UI:

1. At the shell prompt, run `ls` (alias of `list`).
2. Run `edit /hello.lua` and enter this Lua **source**:

   ```lua
   print("Hello from the playtest")
   ```

3. The vendored editor uses **Ctrl** to open its menu, then **S** to save;
   use its displayed menu and **E** to exit. Consult in-game controls for the
   Factorio-to-terminal key mapping rather than assuming Ctrl+S works.
4. Run `ls`, reopen with `edit /hello.lua`, verify the text, exit, then run
   `/hello.lua`. Expect the greeting and a return to the prompt. Binary Lua
   bytecode is not executable; use source files with a `.lua` name.

## Client-owned acceptance checklist

Leave each item unchecked until actually exercised in the supplied build.

- [ ] Fresh world: personal and powered physical computers boot to the shell.
- [ ] Create, save, list, reopen and execute `/hello.lua` using the steps above.
- [ ] Colors, editor highlighting, cursor position/blink, scrolling and text are
      readable at the chosen resolution and UI scale; record rendering defects.
- [ ] Defaults are **51 columns × 19 rows**. Window/display scaling does not change
      guest dimensions. Change startup settings, restart/reload as required, and
      check geometry reconciliation and retained files/editor state. Bounds are
      model limits, not a promise that every size renders well.
- [ ] Text/paste, navigation, modifiers, repeat/release and cell-addressed mouse
      behavior match documented in-game controls without duplicate/world input.
- [ ] Two real clients open one physical computer: both can type into the **same**
      shell/editor, see the same display and observe interleaved shared input.
      This is not two independent sessions or conflict-free collaborative editing.
- [ ] Focus loss, closing one view and disconnecting one viewer release only that
      viewer's held input; the other viewer continues without stuck keys.
- [ ] Closing/reopening the GUI does **not** reboot the OS. Save/reload and a new
      client joining preserve the current session rather than restarting it.
- [ ] Distance, force/surface access and personal ownership restrictions hold;
      power loss pauses execution and power restoration permits continued use.
- [ ] On an upgraded **save copy**, inspect the migration notice and recovery
      location it reports. Verify ordinary files, unsaved legacy drafts, `/rc`
      collisions and legacy startup source remain recoverable. Old callback
      processes/startup code must not automatically execute. Save/reload and
      recheck the recovered content before considering migration accepted.

Report the exact mod/Factorio versions, enabled mods, startup terminal dimensions,
resolution/UI scale, single- or multiplayer context, steps, expected/actual result,
and relevant logs. Preserve a reproducible save copy; screenshots help with UI bugs.

## 0.3.0 blue shell alpha: additional client checks

Only use a supplied, checksum-identified candidate archive and a backed-up test
world. This is a user-authorized alpha, not completed acceptance. Existing computer research
unlocks both physical recipes; personal terminals and original bodies remain VM.
Blue bodies provide built-in commands only: no editor, Lua execution, modules or
world/network APIs. Supply power and open within the existing research/force/
surface/range restrictions. Initialization may precede the first prompt.

The implementation has headless lifecycle and table-backed GUI routing tests,
not native client acceptance. Leave these boxes unchecked until genuinely tested:

- [ ] Open both models, distinguish blue artwork/title/status, and confirm that
      the original VM still supports its existing programs without conversion.
- [ ] Click a blue cell to focus typing without an unsupported-mouse error.
      Individually type, navigate, delete, use history/Tab, then paste CRLF text;
      confirm one-space normalization and that paste alone executes nothing.
- [ ] Switch to another GUI and change resolution/UI scale. The inactive terminal
      must not steal focus or accept stale text, Enter, Reboot or Shutdown.
- [ ] Resize the active terminal and check immediate prompt/cursor redraw before
      typing another character; command/history/job state must remain intact.
- [ ] Run help and file commands, close during pending output/file work, reopen
      and verify the same session and exactly-once committed effects.
- [ ] Cut power during a job, check visible refusal of input/lifecycle controls,
      restore power and verify continued progress without reboot or lost files.
- [ ] Use Terminate, Shutdown and Reboot; verify pending-work semantics and
      committed-file retention. Refused lifecycle requests must be visible.
- [ ] Revoke research or move beyond range/across force/surface boundaries;
      stale-view keyboard, text/paste and controls must change no runtime data.
- [ ] Keep original VM and blue viewers open simultaneously; input/display must
      target the intended backend. Then repeat shared-view behavior with real
      clients and join during partial input plus a pending job.

Record exact archive hash, Factorio version, startup geometry, UI scale, event/job
state and reproducible steps. Keep screenshots/logs outside the repository. Real
graphical latency and multiplayer joining remain blocking acceptance gates.
