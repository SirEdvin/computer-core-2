# Guest local files and ROM

The isolated VM exposes virtual `fs` and `io` services. They never call native IO
or the old peer-mount resolver. `/mnt/...` is an ordinary local path, not a bridge
to another computer. Paths use the existing canonicalization primitive: NULs and
paths over 1,024 bytes are rejected; `.` and `..` are normalized within root.
No normalized path can escape to the host filesystem.

`/rc` is read-only and comes exclusively from the pinned vendor manifest.
`tools/guest_rom_source.py` deterministically quotes the allowlisted sources into
`scripts/guest/rom.lua`, because Factorio cannot read arbitrary packaged text
files at runtime. These are source strings, not host-evaluated ROM modules or
native bytecode. The verifier rejects a stale generated module. BIOS source is
included separately for the future boot driver and is not mounted over a user's
local `/bios.lua`. ROM content does not count against local disk quota.

## Disk and handle semantics

Local content limits retain the existing 1,048,576-byte and 2,048-node quotas.
Directories, sorted listings, existence/type/size queries, recursive mkdir and
delete, copying and moving remain local-only. Copy/move build and quota-check the
entire proposed tree before replacing disk state. ROM writes, moves and deletion
are rejected. Copying an OS source to writable local storage is allowed.

Supported open modes are r/w/a, optional binary marker, and corresponding + modes.
Mode strings are allowlisted rather than repaired. All content is stored as bytes;
binary mode does not invoke a native file API or transform source encodings.
Each handle is a hidden guest object containing canonical path, permissions,
zero-based byte offset, staged content and closed/failed flags. Public method
objects contain symbolic service IDs and guest references only, never host
closures. Both fs dot calls and io colon calls resolve the same durable handle.

Reads support counts, a/*a, l/*l and L/*L, explicit nil EOFs, and line iterators.
Read results are capped at 65,536 bytes: larger files remain readable in chunks.
Seek supports set/cur/end and rejects negative/out-of-quota offsets atomically.
Writable seeks beyond EOF are zero-padded on the next successful write.
There are at most 64 open handles and 4,194,304 retained handle-content bytes.
Closing releases those quotas, clears retained content and invalidates all aliases.
Collection discards unreachable unclosed handles without silently committing
staged writes. The engine verifies bound handles and offsets survive collection.

## Nontruncating replacement

Opening in w stages an empty replacement without truncating the saved file.
Writes update the handle only after content and disk quota admission. Flush/close
commit the complete staged replacement after rechecking current disk quotas.
Explicit successful flush publishes a new committed version. Append snapshots the
current content and stages additions; concurrent handles commit deterministically
in instruction order, with the last successful replacement winning.

A quota-failed write marks the handle failed, preventing a later close from
publishing a partial replacement. Close still releases the failed handle and
reports the failure. The full-disk engine fixture verifies a rejected replacement
and copy retain the prior file and do not create a destination. Abandoned staged
writes likewise leave saved content intact. Readers retain the admitted content
snapshot even if another handle later replaces or deletes that path.

## Directory host-work admission (task 2.4 incomplete)

Guest directory/metadata operations share provisional work credits: 1,048,576
units per computer and 2,097,152 across the scheduler per explicit simulation
tick. Repeated dispatch and separate-process reload retain same-tick counters;
later ticks renew them. Untimed harness calls receive fresh dispatch credits.
Standalone VM runs use per-quantum credits unless a shared context is supplied.

Path normalization reserves weighted input work. Listings charge candidate-path
scanning, every host sorting comparison and guest result insertion. Directory
creation/copy/move charge staging and quota scans; delete stages all matching
paths and admits the final removal loop before touching disk state. Ordinary
metadata queries, path helpers and free-space scans use the same admission scope.
Callbacks are ephemeral host arguments, never stored in guest state.

Exhaustion raises a catchable `per-computer filesystem work limit exceeded` or
`aggregate filesystem work limit exceeded`. Admitted work remains spent on
failure, but no partial directory mutation is committed. Copy/move also validate
every resulting descendant path against the 1,024-byte limit before publishing
the proposed tree, not just the requested destination root.

Engine checks exercise repeated sorted listings from four machines with 600-file
trees, zero-credit guest calls, mid-operation mutation refusal, metered sorting
comparisons, overlong transferred descendants, reload and later-tick recovery.
Handle reads/seeks and source lookup also use these credits, as described below.
Open/write/flush/close also use these credits. Collector cleanup remains governed
by collector work rather than guest file-service credits. Work units are
provisional, not measured production latency or heap bytes.

## Read and seek host-work admission (task 2.4 incomplete)

Counted reads charge one fixed unit plus clipped output bytes, not the whole
backing file. Read-all charges its admitted output. EOF attempts and seeks charge
one unit. Line reads reserve a probe of at most 65,537 bytes, charge copying and
scanning that probe, and then admit the result copy before changing the offset.
A disk-sized file without a newline therefore cannot cause an opaque megabyte
scan; line-size validation still includes a terminating newline as before.

Both fs dot calls (including binary reads), io colon calls and line iterators use
the same budget. A refused individual read or seek leaves its offset/content and
closed/failed flags unchanged; iterator refusal does not auto-close the handle.
Multi-format io reads admit each format in order: earlier successful formats may
have advanced the offset if a later format fails, as with other IO errors.
Source lookup through guest loadfile/dofile admits path work before compilation;
the existing shared compiler budget still accounts for compilation itself.

Engine checks cover zero-credit reads/seeks, clipped tiny reads from a megabyte
file, overlong lines, exact line-length boundaries, refusal after scanning but
before result copying, ordinary retry, repeated reads from four machines and
same-tick separate-process reload/later-tick renewal. No new credits or callbacks
are stored in handles; they share the directory service's durable counters.

## Open, write and commit admission (task 2.4 incomplete)

Open reserves canonical-path work and fixed symbolic-handle construction before
retaining any handle/content quotas. Contents are immutable string references,
not native copies. Failed guest fs/io opens retain their nil/error return contract.

Writes charge operand handling and disk-quota scans, then reserve the complete
reconstruction before changing staged text, offset or retained-byte counters.
The provisional copy estimate is one fixed unit plus six byte passes charged in
eight-byte blocks over the resulting staged size. It covers the fixed substring,
zero-padding and concatenation pipeline; a maximum-quota file reconstruction
fits a fresh per-computer budget. writeLine also charges its extra newline copy.
Multiple operands are admitted in order: previously successful operands remain
staged if a later operand fails. Budget refusal does not mark a handle failed;
actual content-quota failure retains the existing failed-write contract.

Flush admits path validation, quota scanning and publication before changing the
saved file. Close reserves cleanup before attempting flush, distinguishing spend
callback refusal from ordinary IO/content errors without matching error strings.
A budget-refused close keeps the open draft, offset and quotas for later retry;
a failed-content close still releases the handle without publishing its draft.
Iterator creation, io.type and automatic iterator close also receive admission.

Engine checks cover zero-credit opens/mutations, refusal after partial admission,
disk-sized reconstruction, four-machine repeated writes, same-tick reload and
later-tick renewal, draft save/reload followed by exact successful close, and the
existing nontruncating content-quota path. This does not establish heap-byte or
production tick-latency bounds and does not authorize workbench cutover.

## Evidence and remaining integration

The isolated engine scenario executes actual guest fs/io calls, reads vendored
ROM bytes, writes and seeks, iterates lines, copies/moves/deletes local trees and
checks close errors. A separate-process reload preserves an open read/write
handle at offset two; guest execution reads `cd`, writes `XY`, and commits the
expected `abcdXY` content after resuming with an event.

The actual pinned BIOS, shell and both editors now exercise Recrafted's startup
filesystem/IO adapters in the separate guest workflow, including dirty-buffer
reload and exact save/reopen/execute checks. This is headless service evidence,
not graphical or multiplayer acceptance. Migration of legacy `/rc` collisions
remains task 5.3; the existing workbench is unchanged and no existing user
filesystem has been migrated or overwritten.
