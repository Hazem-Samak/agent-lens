# M5 — Duplicate / PATH diagnostics

> Parent-approved specification; M5 is implemented and independently accepted.
> Read `briefs/README.md` first. The orchestrator owns the brief and independently
> reruns acceptance (D-014). Do not treat the machine snapshot below as a fixed
> requirement.

## Goal

Extend `agent-lens scan` so each registry tool reports the live executable entries
visible on the resolved login-shell PATH, the first live PATH winner, same-target
aliases, and distinct shadowed targets. Show invalid entries only when there is
literal filesystem evidence (for example, a broken symlink, a non-executable file,
or a directory at the candidate path). Preserve the existing tri-state install
state and the detector's bounded version query.

This is local, offline PATH diagnostics only. It is not an installation-history
or filesystem-cleaning feature.

## Explicit scope and exclusions

In scope:

- Inspect the ordered `ShellEnvironment.pathEntries` for each existing registry
  definition, with each entry interpreted using the current working directory.
- Inspect only the registry's declared `extraSearchRoots` when the existing
  detector needs them to represent `installedNotOnPath`; preserve the detector's
  order and tilde-expansion behavior.
- Report PATH ordering, live candidate paths, same-target aliases, distinct
  target groups, and evidence-backed invalid entries.
- Add focused synthetic tests and integrate the diagnostic report with `scan`.

Out of scope:

- Network access, latest-version checks, UI, install/update/uninstall operations,
  new detectors, generic cleanup, or scanning outside PATH and the detector's
  declared extra roots.
- Persistent installation history, ownership assertions, or claims that a
  missing file, absent package manifest, or empty directory is orphaned/stale.
- Counting or reporting a path that is wholly absent. Absence is normal, not
  historical evidence.
- Changes to the detector registry schema or default registry data.

No latest version may be probed. `nil` for an installed version stays unknown and
renders as a dash. A missing tool is a normal `notInstalled` result. The source
label from `ToolDetector.classifySource(resolvedPath:)` remains a path-based
heuristic, not proof of package ownership.

## Existing API facts (verified against current sources)

The APIs available to M5 include:

- `ToolDetector.detect(in:) -> DetectedTool`, which selects the first live
  executable from `ShellEnvironment.pathEntries`, then tries its configured
  `extraSearchRoots` if PATH had no live match.
- `ToolDetector.extraSearchRoots`, `versionQuery`, `queryVersion`, and
  `classifySource(resolvedPath:)`.
- `ShellEnvironment.pathEntries`, `raw`, and `isDegraded`.
- `DetectorDefinition.makeDetector(...)`, its `extraSearchRoots`, and
  `DetectorRegistry.loadDefault()`.
- `ScanRenderer.render(tools:)`.

There is no `ToolDetector.existingPath`, `existingPaths`, or `ScanEntry` API.
The existing detector's first-match helper is private. Do not call or assume a
new query method exists. M5 must add its own diagnostic models/scanner and may
add a diagnostics-specific renderer (for example, under `Diagnostics/`) rather
than changing the existing `ScanRenderer`.

The diagnostic PATH walk is intentionally independent so it can see broken
symlinks and other non-winning entries. Its winner policy must nevertheless
match `ToolDetector.detect(in:)`: a candidate is live only if it resolves to a
regular executable file, and the first such PATH candidate wins. Before showing
a winner, compare the diagnostic result with `DetectedTool.entryPath` and
`resolvedPath`. Normalize a relative `entryPath` against the same current
working directory before comparing it with the diagnostic's absolute entry
path; compare the resolved target as well. If the normalized entry or target
disagrees, do not silently choose one or claim a winner; surface a clear
consistency failure/unavailable diagnostic and cover that seam with a test. Do
not add duplicate version queries to the walk.

The existing detector remains the source of install state, selected executable,
source label, and selected version. Its version query is bounded and receives
`ShellEnvironment.raw`; do not execute losing candidates merely to list them.

## File boundaries

M5 may add:

- `Sources/AgentLensCore/Diagnostics/*.swift` (new models, enumerator,
  diagnostic report/rendering as needed).
- New files under `Tests/AgentLensCoreTests/` for the diagnostics fixtures.
- A narrow `Sources/agent-lens/main.swift` `scan` integration.

Treat these existing files and all unrelated files as read-only:

- `Sources/AgentLensCore/Detection/ToolDetector.swift`
- `Sources/AgentLensCore/Detection/DetectorRegistry.swift`
- `Sources/AgentLensCore/Detection/ScanRenderer.swift`
- `Sources/AgentLensCore/Environment/ShellEnvironmentResolver.swift`
- The bounded process runner, `DefaultDetectors.json`, and `Package.swift`
- `DECISIONS.md`, `AGENT_LENS_SCOPE.md`, and other briefs/plans

If implementation truly needs a shared seam in a read-only file, stop and ask the
orchestrator for approval before changing it. Preserve `debug-env`, unknown
command behavior, and the usage text exactly.

## PATH entry and candidate semantics

For every detector, walk `pathEntries` in order. Preserve the original slot
number and text, including repeated, empty, and relative roots. An empty root
means the current working directory; a relative root is resolved against that
same working directory. Do not discard empty components or silently switch to
the process's inherited PATH.

Inspect candidate directory entries using `lstat`-equivalent semantics so a
broken symlink itself remains observable. A candidate is live only when the
entry resolves to an existing regular file with executable permission. Classify
observed entries with literal evidence, such as:

- direct live executable;
- live symlink and its canonical resolved target;
- broken symlink (target does not resolve to an existing target);
- symlink whose target exists but is not a regular executable file;
- non-executable regular file;
- directory named like the executable; or
- another observed non-regular entry, described by its actual type.

A directory, non-executable file, broken link, or other invalid candidate does
not win. Continue until the first live candidate. Skip absent candidates
quietly; do not create a missing/orphan/stale record. Do not infer that an
observed broken symlink proves a deleted install or previous file.

Do not execute non-winning entries. The existing detector may query only its
selected PATH winner (or its configured extra-root result when no PATH candidate
is live), using its existing bounded query and explicit `ShellEnvironment.raw`.

## Slot, alias, and target counts

Keep three concepts visibly separate:

1. A PATH slot is one ordered occurrence in `pathEntries`. Repeated occurrences
   of the same normalized candidate path retain their slot numbers but are not
   additional installations.
2. A distinct entry path is a candidate path normalized to an absolute,
   standardized path relative to the current working directory, without
   resolving the candidate's own symlink. Two different entry paths that lead
   to one canonical target are same-target aliases.
3. A canonical target is the existing resolved target path of a live candidate.
   Group live entry paths by this path only. Two different canonical targets
   are separate path-based targets/installations for this report. This does not
   claim that they have different contents, inodes, or package ownership; do not
   claim hardlink/content equivalence without separate implementation and tests.

Counts must use unique normalized entry paths and canonical targets, not raw
slot occurrences:

- `repeated PATH slots`: extra occurrences of an already-seen normalized
  candidate entry path; retain their positions, but do not add installation or
  alias counts.
- `same-target aliases`: within each canonical-target group, the number of
  distinct entry paths beyond the first. A repeated slot for one entry path
  contributes zero aliases.
- `shadowed installations`: distinct canonical-target groups other than the
  winner's target group, ordered by the first live PATH slot in each group. A
  later path alias to the winner's target is not a second installation.

If the implementation uses different display names for these metrics, their
definitions must remain equally explicit. Do not emit an ambiguous `duplicates`
count that conflates repeated slots, aliases, and distinct targets.

## Tri-state and extra-root behavior

Preserve `installedAndOnPath`, `installedNotOnPath`, and `notInstalled` exactly.

- A live PATH winner is shell-selected and must agree with `ToolDetector.detect`.
- If no live PATH entry exists but the existing detector finds a declared
  `extraSearchRoots` candidate, report `installedNotOnPath`, identify that known
  root as off-PATH, and do not imply that the shell selects it.
- If neither PATH nor the declared extra roots has a live executable, report
  `notInstalled`; do not search other locations.
- If an extra root overlaps a PATH candidate, deduplicate by normalized entry
  path/canonical target and annotate both observations as needed. Never count the
  same candidate once as a PATH installation and again as an extra-root install.

When `ShellEnvironment.isDegraded` is true, surface a clear warning that PATH
came from the documented fallback and that the report may not represent the
login shell's authoritative PATH. Do not present degraded PATH results as
complete or authoritative.

## Report expectations

Keep the existing registry-driven tool rows and existing state/version/source
meaning. Extend `scan` with clearly labeled, ordered diagnostic details. For a
PATH-installed tool, show its verified winner, live entry paths and targets,
invalid observed entries (if any), repeated-slot count, same-target-alias count,
and shadowed-installation count. For an off-PATH tool, label the found root as
known/off-PATH, not as the shell winner. For a missing tool, show the existing
neutral not-installed state without treating it as an error. Unknown version is
a dash. A degraded-environment warning must be visible when applicable.

Exact prose/layout is an implementation choice; the state, ordering, evidence,
and count definitions above are acceptance requirements. Do not promise fixed
zero-duplicate, stale, or orphan counts.

## Synthetic acceptance matrix

All filesystem fixtures must live under an isolated scratch root injected into
tests. Tests must not create, remove, or alter real tool installations or
`~/.local/bin` entries. Cover at least:

1. Two distinct live executable targets in ordered PATH roots: first live target
   wins; the other is reported as a later shadowed target.
2. Two distinct candidate paths resolving to the same target: one target group,
   one additional same-target alias, and no second installation claim.
3. A repeated PATH directory/slot: slot evidence is retained but installation,
   target, and alias counts are not inflated.
4. Broken symlink, non-executable file, and directory before a later live
   candidate: each invalid entry is classified with literal evidence and does
   not win; the later live candidate wins.
5. Invalid-only/absent candidates: no live winner and `notInstalled`, unless a
   declared extra root has a live executable; absent candidates produce no
   historical/orphan record.
6. Empty and relative PATH roots resolved against an injected current working
   directory, with no fixture leakage between working directories.
7. A live executable only in a known extra root: `installedNotOnPath`, with no
   implication that it is shell-selected.
8. A PATH/extra-root overlap: the candidate is not double-counted.
9. Missing tool, unknown version (rendered as a dash), and degraded environment
   (warning shown).
10. Stable ordering and count assertions for live candidates, aliases, repeated
    slots, shadowed targets, and invalid entries.
11. A seam test that the diagnostic's reported winner agrees with the existing
    detector's `entryPath` and `resolvedPath`, including relative/empty roots.

New M5 tests must demonstrate RED before implementation for the intended
behavior (not merely fail to compile), then pass after implementation. The full
existing M0–M4 suite must remain green; the accepted pre-M5 baseline is 34 tests.
The orchestrator reruns the full acceptance independently and records raw,
unedited terminal transcripts in the walkthrough per `briefs/README.md` and
D-014. Do not fabricate transcript text from a summary.

## Machine-state cross-check (measured at run time, not a fixed assertion)

The last independent machine observation reported these PATH shapes:

- Codex: 1 distinct live entry path / 1 canonical target.
- OpenCode: `~/.opencode/bin/opencode` and `~/.hermes/bin/opencode`: 2 paths / 1 target.
- Grok: `~/.grok/bin/grok` and `~/.local/bin/grok`: 2 paths / 1 target.

These are a dated snapshot, not timeless requirements. Do not hardcode versions,
paths, or a clean-zero-duplicates expectation. The last checked versions were
Codex `0.162.1`, OpenCode `2.0.28`, and Grok `1.0.52`; compare the current live
output at acceptance time.

Use a login+interactive shell for the cross-check. This script reads only PATH,
prints only the three tool names, candidate paths/targets and a parsed
`--version` token, and runs `--version` only for the first live candidate of
each tool. It does not dump the shell environment or execute losing copies:

```sh
/bin/zsh -l -i -c 'python3 -' <<'PY'
import os
import re
import stat
import subprocess

names = ("codex", "opencode", "grok")
slots = os.environ.get("PATH", "").split(":")

for name in names:
    occurrences = []
    for index, root in enumerate(slots):
        entry = os.path.abspath(os.path.join(root or ".", name))
        try:
            mode = os.stat(entry).st_mode
        except OSError:
            continue
        if stat.S_ISREG(mode) and os.access(entry, os.X_OK):
            occurrences.append((index, entry, os.path.realpath(entry)))

    distinct_entries = {}
    repeated_slots = 0
    for index, entry, target in occurrences:
        if entry in distinct_entries:
            repeated_slots += 1
        else:
            distinct_entries[entry] = {"target": target, "slots": [index]}
        if index not in distinct_entries[entry]["slots"]:
            distinct_entries[entry]["slots"].append(index)

    target_groups = {}
    for entry, item in distinct_entries.items():
        target_groups.setdefault(item["target"], []).append(entry)
    aliases = sum(max(0, len(entries) - 1) for entries in target_groups.values())

    print(f"{name}: distinct paths={len(distinct_entries)}, "
          f"distinct targets={len(target_groups)}, repeated slots={repeated_slots}, "
          f"same-target aliases={aliases}")
    for entry, item in distinct_entries.items():
        print(f"  slot(s) {item['slots']}: {entry} -> {item['target']}")

    if occurrences:
        winner = occurrences[0][1]
        try:
            result = subprocess.run(
                [winner, "--version"], capture_output=True, text=True,
                env=os.environ.copy(), timeout=3, check=False
            )
            match = re.search(
                r"[0-9]+(?:\.[0-9]+){1,3}(?:-[0-9A-Za-z.]+)?",
                result.stdout
            ) if result.returncode == 0 else None
            print(f"  first-live version={match.group(0) if match else '–'}")
        except (OSError, subprocess.TimeoutExpired):
            print("  first-live version=–")
    else:
        print("  first-live version=– (no live PATH candidate)")
PY
```

A human may compare this snapshot to `agent-lens scan`. It is a read-only
cross-check and must not be used as synthetic acceptance or modify installations.

## Build/test invocation and acceptance evidence

The current Command Line Tools setup may need the installed Swift Testing macro
library explicitly loaded. Use an isolated Hermes scratch root for builds and
test fixtures; do not install dependencies or write test files under `/tmp`:

```sh
scratch="$HOME/.hermes/cache/scratch/agent-lens-m5-$(uuidgen)"
mkdir -p "$scratch/fixtures"
AGENT_LENS_TEST_SCRATCH="$scratch/fixtures" swift test \
  --build-system swiftbuild \
  --scratch-path "$scratch/build" \
  -Xswiftc -load-plugin-library \
  -Xswiftc /Library/Developer/CommandLineTools/usr/lib/swift/host/plugins/testing/libTestingMacros.dylib
```

Acceptance requires:

- New regression tests have recorded, intentional RED evidence before code and
  pass after code; the full suite exits 0 and includes all existing tests.
- `agent-lens scan` exits 0 and reports every registry tool with truthful state,
  winner, candidate ordering, and explicitly defined counts. The CLI's
  `debug-env`, unknown-command behavior, and usage text remain unchanged.
- Synthetic fixture acceptance covers the matrix above; no live installation
  directory is mutated.
- The orchestrator reruns acceptance independently and adds raw terminal
  transcripts to the walkthrough. A worker's summary is not acceptance evidence.

M5 is done only after the orchestrator accepts the brief, implementation, tests,
and independent acceptance. The orchestrator has accepted M5; see
`walkthroughs/M5-duplicate-path-diagnostics.md` for the independent acceptance
evidence. This brief remains the requirements record and does not replace that
evidence.
