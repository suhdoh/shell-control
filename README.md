# Shell Control

[![Release](https://img.shields.io/github/v/release/suhdoh/shell-control?label=version&color=d97706)](https://github.com/suhdoh/shell-control/releases/latest)
[![Windows checks](https://github.com/suhdoh/shell-control/actions/workflows/test.yml/badge.svg)](https://github.com/suhdoh/shell-control/actions/workflows/test.yml)
[![License: MIT](https://img.shields.io/badge/license-MIT-blue)](LICENSE)
![Platform: Windows 10 / 11](https://img.shields.io/badge/platform-Windows%2010%20%2F%2011-0078D4)
![PowerShell: 5.1 / 7](https://img.shields.io/badge/PowerShell-5.1%20%2F%207-5391FE?logo=powershell&logoColor=white)
![Menu languages: EN / DE](https://img.shields.io/badge/menu%20languages-EN%20%2F%20DE-629755)

[![Windows Terminal](https://img.shields.io/badge/Windows%20Terminal-333333)](https://github.com/microsoft/terminal)
[![Fastfetch](https://img.shields.io/badge/Fastfetch-4C9A69)](https://github.com/fastfetch-cli/fastfetch)
[![Oh My Posh](https://img.shields.io/badge/Oh%20My%20Posh-D97706)](https://github.com/JanDeDobbeleer/oh-my-posh)
[![eza](https://img.shields.io/badge/eza-629755)](https://github.com/eza-community/eza)
[![Gum](https://img.shields.io/badge/Charm-Gum-FF5FA2)](https://github.com/charmbracelet/gum)
[![Nerd Fonts](https://img.shields.io/badge/Nerd%20Fonts-85%20families-8B5CF6)](https://github.com/ryanoasis/nerd-fonts)
[![WinGet](https://img.shields.io/badge/WinGet-0078D4)](https://learn.microsoft.com/windows/package-manager/winget/)

A compact Windows shell setup with a searchable terminal menu, themed prompts and a hardware overview.

I built this out of laziness: I like good-looking Gum windows and want to customize my terminal however I feel like, without editing config files every time. The defaults just look bad to me. Shell Control puts the things I actually use in one menu, inspired by Charm/Gum and rendered with native PowerShell for Windows.

```text
Shell Control

Appearance   → themes / fonts / prompt / CRT
  Themes     → family → variant
  Fonts      → typeface / size / install fonts
System info  → hardware, network and usage bars
Tools        → command reference / new tab
Setup        → full setup / individual components
Settings     → language / startup Fastfetch
Exit
```

English is the default display language. Search always accepts English and German. The menu uses its own console renderer for stable input and selection; Gum is installed alongside the other shell tools.

**Contents:** [Install](#install) · [Options](#options) · [Themes & fonts](#themes-and-fonts) · [Commands](#commands) · [Remove integration](#remove-profile-integration) · [Development](#development) · [Credits](#credits)

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

The native prompt is the default for fast startup. Oh My Posh is an optional engine using the included minimal configuration. Switch it under **Appearance → Prompt** and open a new tab if your current session retains an earlier prompt hook.

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

## Credits

I do not own the fonts, third-party tools, icons or upstream theme palettes. Fonts are downloaded from **Nerd Fonts**, with the original typeface authors' copyright and licenses preserved. Thanks to those designers, the Nerd Fonts contributors, Charm and all the projects that make this setup possible.

See [third-party credits](THIRD-PARTY.md) for tools, inspiration and themes, and [font credits](FONT-CREDITS.md) for every supported font package and its original notices. Setup installs these credit documents and notices with the configuration. Shell Control's own code is MIT licensed; third-party components retain their own licenses.
