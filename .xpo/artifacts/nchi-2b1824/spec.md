# Short folder label in the composer for an existing agent

## What / Why
The folder chip when messaging an existing agent shows the full path. The new-chat folder button already shows `parent/folder`. Both should read the same way.

## How
- Move `FolderPicker.label(_:among:)` and `abbreviated(_:)` into a shared `FolderLabel` helper in Composer.swift: `FolderLabel.short(_:among:)` and `FolderLabel.full(_:)`.
- `ContextChip` shows `FolderLabel.short(cwd)`, with the tooltip `FolderLabel.full(cwd)`. Without a folder, it shows the agent's name, as today.
- `FolderPicker` uses the same helper; nothing changes there visibly.

## Acceptance criteria
- Messaging an agent in `/Users/me/code/acme/nocchi` shows `acme/nocchi`.
- `FolderLabelTests` pass against the moved helper.
- The `notch-prompt.png` snapshot shows the short label.