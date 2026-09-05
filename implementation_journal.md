# Implementation Journal: Summarization Feature

## Current Status
- **Phase**: 1 (Data & Core)
- **Progress**: Step 1.1 done, build green, 60 tests pass.

## Completed
- [x] **Step 1.1**: `summary_text` end to end in storage.
  - `StoredCallSummary.summaryText` — read by `fetchCalls` / `fetchCall`.
  - `CREATE TABLE` column + `ALTER TABLE` migration for databases that already exist.
  - `CallStore.setSummary(callID:text:)` writes it; `upsertCall` deliberately does not,
    so a status update during recording cannot wipe a stored summary.

## Current Context & Notes
- The summary lives on `StoredCallSummary` only. `StoredCallDetail` reaches it through `.summary.summaryText`.
- SQLite is driven through raw `SQLite3`; `withStatement` takes a one-argument closure.
- Existing `untracked/calls.sqlite` has no `summary_text` yet — the migration adds it on the next app start.

## Next Step
- [ ] **Step 1.2**: `SummarizationProvider` protocol + `SummarizationService`.
- [ ] **Step 1.3**: `MockProvider` for UI work without a live model.
