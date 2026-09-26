---
type: Decision Record
title: SQLite call index through the system SQLite3 API
status: accepted
generated:
  by: agent
  at: 2026-09-26T00:00:00Z
---

# SQLite call index through the system SQLite3 API

**Status: accepted.**

## Context
The [MVP phase plan](../archive/mvp-phase-plan.md) asked for a "small SQLite call index" and local-only storage
under Application Support, not `~/Documents`, because Documents "may be synced by iCloud". It sketched the
`calls`, `transcript_jobs` and `transcript_segments` tables. Why SQLite, and why no wrapper library, is not
recorded.

## Decision
`Storage/CallStore.swift` talks to `calls.sqlite` through `import SQLite3` (the C API shipped with macOS), with no
third-party database dependency. Audio and transcript files sit next to it on disk.

## Consequences
- No dependency to update; every query is hand-written against `sqlite3_*` calls.
- The on-disk format is a contract: the [ponytail cleanup](ponytail-cleanup.md) kept it unchanged.
