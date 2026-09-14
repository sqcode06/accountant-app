# Consistent financial saves (REL-04)

The iOS app now saves transactions, accounts, budget limits, and import rules
as one validated snapshot. Restoring or erasing cannot commit only some of
those parts. `AppDataStore` owns the disk format; `AppDataRepository` is the
app's asynchronous boundary. `AppState` has one serialized writer.

## Existing installations and versioning

The authoritative file remains `Accountant/ledger.json`. Schema versions 1–4
are read with their existing `budget.json` and `classification-rules.json`
companions. All three are validated together, including budget references and
rule identities. Supported stale rule references remain valid and are filtered
when rules run.

If individually readable legacy files disagree, their source bytes are also
quarantined before recovery. A failed quarantine move or marker write cannot
authorize overwriting an otherwise readable primary file.

A healthy load does not rewrite files. The next successful save atomically
replaces `ledger.json` with schema 5, which requires the ledger, budget, and
rules in the same envelope. There is no separate migration marker or interval
where a new ledger depends on old companion data. Version 5 never consults
companion files while unlocked, even if they contain old values or old recovery
markers. Corrupt, incomplete, and unsupported snapshots enter recovery.

The legacy core `JSONLedgerStore` still reads/writes its standalone version-4
format. It rejects version 5. **Older app builds cannot open data saved by this
build**; they must not be used as a downgrade path. Exported `LedgerBackup`
documents keep their existing format and exact date coding.

Legacy companion files and quarantined originals are retained for recovery;
they are never used to repopulate a successfully erased version-5 snapshot.
Erase clears the app's active financial state. It is not forensic deletion of
historical recovery files or previously exported backups.

## Commit and interruption contract

The complete replacement is encoded before writing. Foundation's
[`Data.WritingOptions.atomic`](https://developer.apple.com/documentation/foundation/nsdata/writingoptions)
writes to an auxiliary file before replacing the original. That replacement
is the financial commit point. This contract is about application/process
interruption on local app storage, not a universal hardware power-loss guarantee.

| Interruption or failure | State after reopening |
| --- | --- |
| Before encoding or before atomic replacement | Complete previous data |
| During Foundation's atomic write | Previous or replacement file; unreadable data is protected |
| After replacement, before the caller observes success | Complete replacement, or a recovery lock if its marker remains unresolved |
| During recovery completion | Protected replacement until the durable marker is resolved |
| After acknowledged completion | Complete replacement |

Restore, erase, and Start fresh block competing mutations, cancel the pending
debounce, and await any older writer before committing. They publish the new
visible state only after the save succeeds. A failure preserves existing
unsaved edits and is not queued for an automatic destructive retry. If an error
arrives after a commit, re-reading the authority prevents stale in-memory data
from overwriting the completed replacement. An unacknowledged operation can
therefore have completed on disk; the error remains visible.

Ordinary edits still update memory immediately and use the existing 400 ms
debounce, now writing a full snapshot. Concurrent flush callers join the writer
and wait for changes arriving during a save to drain. Failed ordinary saves
retain their pending changes for retry. Background flushing provides an
opportunity to finish; abrupt termination can precede an unacknowledged save.

Quarantine still records protection before moving an unreadable original.
Replacing a damaged primary cannot unlock it before recovery completion. If
only a legacy companion is damaged, recovery first protects the readable
primary too, preserving the accounts/history needed to recover the old set.
Its marker keeps the replacement locked until recovery completion; companion
originals and their recovery evidence remain intact.
Malformed recovery metadata remains locked and needs manual preservation and
repair; the app does not guess what an unreadable marker intended. This existing
limitation is separate from interruption of the atomic save/marker operations.

## Verification

The original app-level regression failed with a budget-only save failure:
reopening produced a new ledger, old budget, and no lock. The repaired test
checks complete old/new states at every exposed commit boundary.

- `AppDataStoreTests` uses real files for legacy migration, full financial
  equality, empty and nonempty replacements, fault checkpoints, required-field
  validation, quarantine retention, and stale companion isolation.
- `SnapshotReplacementTests` checks failed restore/erase, pending edits, older
  in-flight writers, concurrent flush callers, recovery checkpoints, and invalid
  input. Barriers synchronize writes; delays are only failure timeouts.
- `DataProtectionTests` retains all seven damaged legacy-store combinations and
  checks recovery against the production snapshot repository.
- `RestoreEraseUITests` selects a fixture backup through the real decoder,
  confirms restore, reopens and checks all four financial counts, erases through
  the actual confirmation, then reopens and checks emptiness. The Debug fixture
  bypasses only the OS document picker.

Linux tests validate core and app logic. The native macOS CI result is recorded
in [AppTesting.md](AppTesting.md); SwiftUI and iOS lifecycle claims require that
run. The checkpoint tests inject failures around Foundation's atomic write;
they do not simulate hardware power loss or interrupt Foundation internally.
