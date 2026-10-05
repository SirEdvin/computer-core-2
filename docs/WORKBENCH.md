# Computer workbench 0.1.1

## Interface

The workbench uses Factorio's native frames, titlebar drag handle, close icon,
confirm/danger buttons, scroll panes and monospace editor/output. There is no new
UI library, copied mod code or copied artwork.

- **Terminal:** shell commands, streaming output, and explicitly submitted program input.
- **Files:** browse folders/mounts; create a file or folder; open or run saved Lua.
- **Waypoints:** selected saved location, editable fields and live camera; clear save/delete feedback.
- **Help:** existing shell/API help and concise orientation, not bundled example programs.
- **Editor:** source path, live modified/saved byte count, Save / Save & run, and the
  existing retained-draft/conflict/rebase protections.

The titlebar is draggable. View changes preserve window position. Resolution and
UI-scale events recalculate window bounds without losing source, command or input
drafts. Smaller windows stack forms/actions and scroll vertically rather than
forcing the large-screen layout outside the viewport.

Program state is shown separately from operation feedback. Stop, save, input and
shell commands report their result immediately. Success/error notices expire after
ten seconds; errors have text as well as colour. Terminal submissions refresh the
existing controls instead of destroying the entire window, avoiding repeated focus,
position and input resets. Live output is updated at the normal GUI tick cadence.

The workbench stays inspectable without power. Running programs and submitting
program input still require power; input additionally requires a running program.
Typing into **Program input** no longer triggers listeners per keystroke. Send or
Enter delivers the completed text once. Direct Lua/remote input APIs are unchanged.
Force, surface, research, ownership and range checks still apply.

## Reference mods

Reviewed the original source implementations, not just screenshots:

- Factory Planner, commit `1cc8f6f8855224f314e3e3751fa42e8edac1472f`:
  [title bar](https://github.com/ClaudeMetz/FactoryPlanner/blob/1cc8f6f8855224f314e3e3751fa42e8edac1472f/modfiles/ui/main/title_bar.lua),
  [display fitting and frame layout](https://github.com/ClaudeMetz/FactoryPlanner/blob/1cc8f6f8855224f314e3e3751fa42e8edac1472f/modfiles/ui/base/main_dialog.lua).
  Inspiration: clear native chrome, draggable titlebar, bounded scaled dimensions,
  separated navigation/content and explicit enabled states.
- Recipe Book, commit `e594becf3fafcc930e626a22eb948b06123f98f8`:
  [main window](https://github.com/raiguard/RecipeBook/blob/e594becf3fafcc930e626a22eb948b06123f98f8/scripts/gui/main.lua).
  Inspiration: standard close/action controls, navigation separation and contextual
  controls rather than a wall of unrelated buttons.

Implementation uses existing native Factorio controls instead of importing either
mod or its UI dependencies.

## Wire connection correction

The left/right child entities already sit on the sprite's two leg ends. However,
they were derived from vanilla constant combinators and inherited those entities'
directional `circuit_wire_connection_points`. This added an unwanted second offset.
All four orientations now use zero-relative wire and shadow points, so both red
and green wires end at the foot entity's position. Ports have explicit priority 100
versus the body's 50, allowing foot selection within the overlapping body box.
Existing port positions and connections are retained; no entities are moved or
replaced simply to correct the wire drawing.

## Upgrade and packaging

0.1.1 remains **ALPHA**. Configuration changes rebuild open interfaces while
retaining sessions/drafts. Existing source snapshots/programs are not restarted.
No old Computer Core save migration is added.

The package contains runtime/data, artwork, locale and LICENSE only. README,
`docs/`, `examples/`, development tools and regression fixtures are excluded. All
Lua examples are repository files for copying into an in-game computer manually.

## What is automatically checked

- Real pinned Factorio 2.0.77 base/expansion runs of the actual ZIP, with save/reload
  in a separate process and real wired circuit input/output for examples.
- Data-stage regression assertions for all four zero-relative red/green wire points,
  wire shadows, selection priority and the native style names used by the workbench.
- Table-backed GUI interaction contracts: rendering/navigation, error/success feedback,
  dirty state, conflict/rebase, file actions, explicit input delivery, power guards,
  Stop state, resize/draft preservation, waypoint selection and foreign-element rejection.
- Pure layout bounds at 1280×720, 1920×1080 and 2560×1440 with UI scales 1, 1.5 and 2.
- Package checks prohibit bundled documentation/examples; GUI contract tests load
  source from the archive being tested, not a potentially different checkout.

**The table-backed GUI tests do not render native controls.** They cannot establish
font metrics, visual polish, actual click targets, actual wire drawing, keyboard
focus/scroll behaviour or multiplayer client acceptance. The fixture includes
additional native checks when a real player exists; playerless headless runs skip
those. Complete [CLIENT_CHECKLIST.md](CLIENT_CHECKLIST.md) in a real client and do
not describe screenshots or visual acceptance as verified until that is done.
