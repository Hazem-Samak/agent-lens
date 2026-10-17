# M8 — Copy Path and Reveal in Finder

Status: **draft — planning only**, 2026-10-17 (Africa/Cairo). The user authorized
preparing this brief and correcting M7 delivery notes. Implementation has not
started. The orchestrator must obtain implementation authorization before
creating an M8 branch or dispatching an implementer. Worker/model assignments
are not selected by this brief; verify the live catalog when assigning them.

## Goal and completion boundary

Let the user copy or reveal either the selected executable entry or its resolved
target directly from the existing tool-detail view, with explicit path identity,
truthful unavailable/error states, and native keyboard/accessibility support.

M8 ends when those two actions pass independent behavioral and native checks.
It does not add package management. Authority: scope §§4, 14 (Phase 3), 27.1,
28.2, 29.4/5/11; decisions D-001/002/006/012–014. The M7 exclusion of path
actions remains correct for that historical milestone.

## Verified starting point

- M7 is delivered at `36a3f1cd4ce3c926deadb2565d8e2a6938161c9f`; local,
  tracking, and GitHub `main` matched on 2026-10-17. Recheck the chosen base
  before implementation; later documentation commits may be present.
- `ToolDetailView` already displays Selected Entry and Resolved Target as
  selectable text. It receives an `InventoryEntry`, including its registry ID
  and the complete typed `ToolPathDiagnostic`.
- `diagnostic.selection` is `.winner(candidate)`, `.offPath(candidate:root:)`,
  `.notInstalled`, or `.inconsistent(reason)`. Verified candidate `entryPath`
  is absolute and standardized against the scan's working directory;
  `canonicalTarget` is the optional resolved path. Core already checks that
  this selection agrees with detection. `DetectedTool.entryPath` can be
  relative; do not reinterpret it using the GUI's current working directory.
- Native actions do not exist yet. Rescan, Check Updates, Refresh Updates,
  selection by registry ID, and lifecycle/cancellation already belong to M7.
- The Swift package has no external dependencies. `AgentLensAppSupport` and
  Core have no UI imports; AppKit integration belongs in `AgentLensApp`.

## Behavior contract

1. Add Copy Path and Reveal in Finder beside each of the two existing path
   rows in **tool details only**. Keep text selection and wrapping. Use native
   controls and accessible names/help that distinguish the tool and the entry
   versus target action. Standard keyboard focus and activation must work;
   no new global shortcuts or redesigned layout are required.

2. For `.winner` and `.offPath`, take the entry and target from that selected
   candidate, never from another PATH candidate. Show the absolute entry used
   by the action in its row. Keep the selected symlink/shim entry distinct
   from the recorded canonical target; even identical paths retain clear row
   labels. Off-PATH paths remain labeled off-PATH, not shell winners.

3. An actionable path is a supplied, nonempty absolute filesystem path without
   a NUL character. Reject relative paths and unexpanded `~`; preserve spaces,
   Unicode, quotes, shell metacharacters, and URL-reserved characters literally.
   Validate each field separately. Missing/invalid fields have no enabled
   action and a concise reason. `.notInstalled`, `.inconsistent`, and no
   selected tool expose no enabled path actions. Preserve existing diagnostic
   warnings and never synthesize a root, parent, home, or other fallback path.

4. Copy writes **the exact displayed absolute path** as plain text through
   `NSPasteboard`. Add no shell quoting, escaping, `file://` prefix, or newline.
   Copying recorded text remains useful if the file has disappeared or a failed
   rescan has retained the snapshot; preserve the existing freshness warning.
   Validate before changing the clipboard. Report a failed clipboard write
   visibly and accessibly, without claiming success.

5. Reveal builds a file URL with `URL(fileURLWithPath:)` and requests selection
   through `NSWorkspace.activateFileViewerSelecting`. Reveal the entry itself
   for Selected Entry, including a symlink; reveal the recorded target for
   Resolved Target. Check that the exact filesystem entry still exists at
   activation, using directory-entry semantics so an extant broken symlink can
   still be revealed. If missing or inaccessible, show an actionable message
   suggesting Rescan and send no Finder request. Do not open/execute the tool,
   silently reveal its parent, or resolve a newly retargeted symlink instead of
   the captured target. Finder's API returns no success acknowledgment: a sent
   request alone is not proof that Finder displayed the item. A filesystem race
   after the check remains possible; do not promise atomic selection.

6. Actions operate on the currently displayed tool/path at activation. Clear
   transient feedback when the selected tool or its path values change; do not
   attach a previous tool's error to the next tool. They neither trigger scans
   or update probes nor alter their scheduling, cache policy, or cancellation.

## File boundary and ownership

Future implementation allow-list:

- Modify `Sources/AgentLensApp/ToolDetailView.swift` for path rows and feedback.
- Add `Sources/AgentLensApp/PathActions.swift` for native controls/effects.
- Add `Sources/AgentLensAppSupport/PathActionTarget.swift` for the small typed
  target/eligibility policy needed by the UI and deterministic tests. Keep it
  Foundation/Core-only; reuse `PathSelection` and `PathCandidateObservation`.
- Add `Tests/AgentLensAppSupportTests/PathActionTests.swift` in the existing
  test target. A small value/closure seam may cover action failures without
  touching the real clipboard or Finder; avoid a service/protocol hierarchy.

Keep AppKit calls in the app target. Use native APIs directly; there is no
shell command, new process runner, external dependency, or package change.

DO NOT TOUCH: all other production/test files, `Package.swift`, Core/CLI,
the registry/schema, diagnostics/list/navigation views, inventory service/view
model/environment provider, existing tests, packaging scripts/resources,
scope/decisions/README/indexes, prior briefs/walkthroughs, and external M7
evidence. A necessary boundary change returns to the orchestrator with the
exact reason and proposed files before editing. After acceptance the parent
owns a new `walkthroughs/M8-path-actions.md` and status-document updates.

Additional exclusions: install/upgrade/uninstall/delete/relink/pin, actions for
shadowed or invalid diagnostic candidates, new detectors/managers/categories,
settings, history/persistence, background work, CI, signing, notarization,
distribution, and unrelated default-TMPDIR/toolchain repairs.

## Implementation sequence and proof

1. **Baseline.** Confirm implementation authorization, the base commit, clean
   branch ownership, and protected-file hashes. Run the full existing Swift
   gate in fresh scratch. An unrelated baseline failure is a reported blocker,
   not permission to broaden M8. Keep one implementation branch; reviewers
   remain read-only. The orchestrator owns independent acceptance (D-014).

2. **Behavior.** Add a `PathActionTests` suite and implement the target policy
   with the narrow native integration. Obtain a behavioral RED failure, rather
   than only a compilation failure, for the intended action behavior. Prove:
   winner/off-PATH paths; symlink entry versus target; identical paths; absent,
   relative, empty, NUL and inconsistent inputs; literal special characters;
   vanished paths and retained snapshots; the current selection; clipboard
   failure; and no Finder request after a failed existence check. Tests use
   synthetic fixtures and fakes, never the user's tools, clipboard, or Finder.
   Tiny injected closures can test dispatch/error policy where needed; native
   API behavior still requires the next step.

3. **Native.** Build the actual product with the existing builder. Exercise
   both rows against safely observed live paths without changing installed
   tools: read clipboard text back and observe Finder selecting the intended
   item. For deterministic symlink/missing-file cases, use a test-owned
   executable and symlink under approved scratch, supplied through the existing
   service injection in an isolated native host. The host must reuse unchanged
   product views/action code. Remove a fixture after scanning and verify Reveal
   reports it missing while Copy retains the recorded text. Verify keyboard
   activation, accessible labels/error feedback, wrapping at a narrow width,
   and switching/rescanning without stale targets or feedback. Record host
   observations separately from actual-product observations. Keep the shipped
   registry and shell configuration unchanged; add no product fixture mode.
   Keep automated clipboard checks isolated; preserve/restore the prior
   clipboard during native smoke checks where feasible and document limitations.

4. **Acceptance.** Rerun the full Swift suite and existing packaging gate,
   inspect the exact allow-list diff/hashes, and retain raw stdout/stderr, exit
   codes, and native evidence. The parent must observe the checks pass and
   record technical acceptance; user visual approval is a separate gate.

## Acceptance commands

Run from the repository root after implementation is authorized. These are
future command shapes, not results from drafting this brief. Use a fresh
scratch root outside the repo/protected paths and retain logs for each command:

```sh
m8_root="$HOME/.hermes/cache/scratch/agent-lens-m8-$(uuidgen)"
mkdir -p "$m8_root/tmp"

env -u AGENT_LENS_TEST_SCRATCH -u AGENT_LENS_TEST_PRODUCTS \
  TMPDIR="$m8_root/tmp" swift test --scratch-path "$m8_root/full-suite"

TMPDIR="$m8_root/tmp" python3 scripts/build-dev-app.py \
  --scratch-root "$m8_root/dev-app" --configuration debug
TMPDIR="$m8_root/tmp" python3 Tests/Packaging/test_dev_app_bundle.py \
  --app "$m8_root/dev-app/AgentLensApp-debug.app"

git diff --check
```

Expected: all commands exit 0; all baseline tests plus the new suite pass
(M7 recorded 222 Swift and 9 packaging tests; remeasure rather than hardcoding
future counts). Default-Darwin-TMPDIR portability remains an existing caveat;
the command supplies an invocation-local `TMPDIR` rather than fixing it.
For the known Swift Testing macro-discovery failure only, use the M7 fallback
in a separate fresh build directory, with no package/toolchain modification:

```sh
test -r /Library/Developer/CommandLineTools/usr/lib/swift/host/plugins/testing/libTestingMacros.dylib
env -u AGENT_LENS_TEST_SCRATCH -u AGENT_LENS_TEST_PRODUCTS \
  TMPDIR="$m8_root/tmp" \
  swift test --build-system swiftbuild --scratch-path "$m8_root/full-suite-explicit" \
  -Xswiftc -load-plugin-library \
  -Xswiftc /Library/Developer/CommandLineTools/usr/lib/swift/host/plugins/testing/libTestingMacros.dylib
```

If that plugin is unavailable or the failure is different, report the exact
failure rather than installing or modifying tooling. A green filtered suite
alone is insufficient. EVIDENCE: raw behavioral RED/GREEN and full-gate logs,
protected-file comparison, product/host native observations, and any unproven
claims. DONE WHEN: independent technical acceptance and explicit user visual
approval are recorded; Git delivery requires its own session authorization.
