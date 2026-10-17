# Safety and security

Shell Control changes shell configuration, installs software and registers per-user fonts. Review the source and use a release from this repository. The project is provided without warranty under its MIT license; the measures below reduce specific risks and are not a security certification.

## Implemented protections

- Only dependency workers request elevation. Full setup coordinates separate workers from the original user's process. Start setup without administrator privileges; it cannot remove privileges inherited from an already elevated parent.
- New installations require a dedicated empty directory. Existing installations must be recognizable. Drive roots, system directories, source-tree overlaps, unrelated populated directories and paths through junctions or symbolic links are rejected. This guard prevents accidental target selection; its marker is not an authenticity check against an attacker who can already edit the directory.
- Persistent configuration changes use a temporary file on the same filesystem, flush it, then replace the destination. Existing versions are kept with unique names in a sibling `.shell-control-backups` directory. Filesystems that do not support the replacement operation fail rather than fall back to truncating the destination.
- A named mutex serializes cooperating Shell Control writers. Snapshot hashes reject detected intervening edits. Other editors do not participate in the mutex, so arbitrary simultaneous external edits cannot be completely ruled out. Close other settings editors while making changes.
- JSON is parsed before a guarded save. Failed validation, stale snapshots, locked files and replacement failures are covered by tests that verify the original contents remain intact.
- Font archives use pinned upstream URLs and SHA-256 digests. Dependency programs are installed through WinGet. Neither mechanism eliminates all upstream supply-chain risk.
- The profile remover checks the selected installation path, supports `-WhatIf`, preserves unrelated profile code and backs up replacements.

## Limits

This is not an all-or-nothing installer. A failed later stage can leave earlier programs, fonts or configuration installed. Power loss, storage faults, malicious local processes, terminal escape sequences in external data and vulnerabilities in dependencies are outside the guarantees of the file-writing safeguards. An installation directory writable by your account contains executable scripts; do not run an untrusted or modified copy with administrator privileges.

Automated checks cover isolated fixtures under Windows PowerShell 5.1 and PowerShell 7. They do not exercise the complete UAC/WinGet/font installation flow on a fresh machine, and are not a penetration test. Keep a separate backup of important files. Do not publish logs, hardware caches or configuration screenshots containing private machine or network information.

## Reporting

For a suspected vulnerability, use the repository's private vulnerability reporting feature if available, or contact the maintainer through GitHub before publishing exploitation details. Avoid including credentials, tokens or personal configuration in reports.
