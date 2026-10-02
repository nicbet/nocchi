# Walkthrough: short folder labels in both composer chips

## What and why
The new-chat folder button showed short labels ("acme/webapp", `c0957e8`). The chip when messaging an existing agent still showed the full path ("/Users/me/code/acme/nocchi"). Both now use the same label.

## How
- The label logic moved out of `FolderPicker` into a small shared `FolderLabel` enum in Composer.swift:
  - `FolderLabel.full(_:)`: the whole path, with home as `~`. Used for tooltips.
  - `FolderLabel.short(_:among:)`: the folder and its parent. Folders right under home stay whole (`~/Projects`), and a parent is added while another folder in `among` would read the same. Only the folder menu passes `among`, because it lists several folders side by side; a single chip doesn't need it.
- `ContextChip` (messaging an agent) shows `short(cwd)` with `full(cwd)` as the tooltip, and still falls back to the agent's name without a folder.
- `FolderPicker` is `private` again; the tests use `FolderLabel.short` directly.

## Checks
- `FolderLabelTests` were renamed to use the helper and are unchanged otherwise.
- The `notch-prompt.png` snapshot now gives the primary agent a real folder, so the short label is visible there. Before, the mock agents had no folder, and the chip showed the name.