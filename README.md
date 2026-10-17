# Shell Control

A compact Windows shell setup with a searchable terminal menu, themed prompts and a hardware overview.

```text
Shell Control

Themes       → theme family → variant
Fonts        → typeface / size / install fonts
Prompt       → native / Oh My Posh
System info  → hardware, network and usage bars
Tools        → command reference / new tab
Setup        → dependencies / fonts / profiles / themes
Settings     → language / CRT / startup Fastfetch
Exit
```

English is the default display language. Search always accepts English and German. The menu uses its own console renderer for stable input and selection; Gum is installed alongside the other shell tools.

## Install

Requires Windows 10/11 and [WinGet](https://learn.microsoft.com/windows/package-manager/winget/). Download this repository as a ZIP and extract it, or clone it:

```powershell
git clone https://github.com/suhdoh/shell-control.git
cd shell-control
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\Install.ps1
```

Setup installs Windows Terminal, PowerShell 7, Fastfetch, eza, Gum and Oh My Posh. Dependency installation requests one UAC elevation when needed. Fonts and configuration are installed for the current user. Package and font tasks show progress inside the menu.

The default destination is `%LOCALAPPDATA%\ShellControl`. Existing PowerShell profiles are backed up and supplemented with one managed import block. Existing Terminal profiles are retained; three Shell Control profiles are added for PowerShell 7, Windows PowerShell 5.1 and CMD. ISE loads the shared functions without the console greeting or menu.

If both the current-user and machine execution policies prevent local profiles and no organization policy applies, setup enables `RemoteSigned` for the current user. Machine and organization policies are not changed.

Open a new Terminal tab and run:

```powershell
shell-menu
```

## Options

```powershell
# All verified font families, rather than the smaller recommended collection.
.\Install.ps1 -FontPack All

# Keep the current Terminal profiles and default profile; only import the themes.
.\Install.ps1 -PreserveTerminalProfiles

# Configure an existing installation without downloading programs or fonts.
.\Install.ps1 -SkipDependencies -SkipFonts

# Custom destination.
.\Install.ps1 -InstallPath D:\ShellControl
```

`-NoProfiles`, `-NoTerminal` and `-NoInteractive` are available for selective or unattended configuration. Setup logs and timestamped backups are stored below the installation folder. Re-running setup replaces its own import block rather than appending duplicates. Existing language and prompt preferences are retained.

## Themes and fonts

Theme families include Amber 340, Osaka Jade, Matrix, Dark Crimson, SynthWave 84, Rosé Pine, Catppuccin and Gruvbox. Rosé Pine, Catppuccin and Gruvbox variants are nested beneath their families. Fonts and prompts use the Terminal palette where supported.

The verified font catalog contains 85 families. The full pack downloads 63 upstream Nerd Font archives; the recommended pack contains Terminess, Gohu, JetBrains Mono, Cascadia Mono, IBM Plex Mono and Meslo. Archives are pinned to Nerd Fonts v3.5.1 and checked against SHA-256 digests. Font licenses are copied with the installed files. Fonts that lack the required symbols or have incompatible character metrics are excluded. No font binaries are redistributed in this repository.

Font choices in the menu are limited to installed families. A newly installed font may require a new Terminal tab before Windows refreshes its font cache. Natural glyph metrics are used; the retro Terminess preset retains a small spacing adjustment.

The native prompt is the default for fast startup. Oh My Posh is an optional engine using the included minimal configuration. Switch it under **Prompt** and open a new tab if your current session retains an earlier prompt hook.

## Commands

```powershell
theme rose
theme mocha
theme gruvbox-dark-soft
font jetbrains
font-size 14
crt toggle
fastfetch
commands
commands -Search font
treload
```

The command reference explains the available shortcuts; opening a reference never executes its example. `l`, `la`, `ll` and `ls` use eza. CMD has its own styled profile, listing macros and `shell-menu` launcher.

In system info, use arrow keys or Page Up / Page Down to scroll, `R` to refresh and Escape to return. Usage is displayed in Windows-style GB units. Hardware and network values are detected on the target computer; no example hostname, IP address or hardware model is shipped.

## Remove profile integration

```powershell
.\Uninstall.ps1 -WhatIf
.\Uninstall.ps1
```

This removes the managed PowerShell import blocks. Runtime files, fonts, dependencies and Terminal settings are deliberately retained. Restore Terminal settings from the installation's `backups` folder to revert the imported themes and profiles.

## Development

```powershell
powershell.exe -NoProfile -File .\tests\Test-Project.ps1
pwsh -NoProfile -File .\tests\Test-Project.ps1
```

Tests use isolated settings and profile fixtures. They do not install programs, register fonts or change real Terminal settings. A fresh-machine installation is a separate integration check.

See [THIRD-PARTY.md](THIRD-PARTY.md) for upstream projects and theme notices. Shell Control is MIT licensed; dependencies and fonts retain their own licenses.
