# Changelog

All notable changes to TokenScope should be documented here.

This project follows explicit versioned release notes. Dates use `YYYY-MM-DD`.

## Unreleased

- Added privacy-preserving tool event extraction and storage for Claude/Codex logs.
- Added repeated file read waste signal in the popover.
- Added working-directory path reconciliation and repeated-read session detail rows.
- Added repeated broad-search waste signal for `rg`, recursive `grep`, and `find`.
- Added repeated directory-listing waste signal for `ls`, `tree`, and shallow `find`.
- Added repeated failed-command waste signal using Claude tool results and Codex rollout failure metadata.
- Added parser edge fixtures for Claude and Codex.
- Added supported provider formats documentation.
- Added token waste analysis research notes.
- Added manual pricing catalog update documentation.
- Added first-pass session detail, diagnostics, and database maintenance controls.
- Added dark mode support by switching the popover palette to semantic AppKit colors.
- Surfaced refresh failures with the underlying error message and a compact warning row on the Overview tab.
- Added a first-run onboarding empty state pointing to `~/.claude` and `~/.codex` when no local usage has been found yet.
- Added tooltips to maintenance buttons and the Waste Signals / Optimization Tips section headers.
- Added a scope-themed menu bar icon and app icon.

## 0.1.0 - Local Test Builds

- Native macOS menu bar app skeleton.
- Local Claude and Codex scanning.
- Normalized usage model.
- SQLite persistence.
- Incremental ingestion index.
- Popover summaries and analytics.
- Unsigned DMG packaging.
