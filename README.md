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

English is the default display language. Settings pickers highlight the saved value when reopened. Search always accepts English and German. The menu uses its own console renderer for stable input and selection; Gum is installed alongside the other shell tools.

**Contents:** [Install](#install) · [Options](#options) · [Themes & fonts](#themes-and-fonts) · [Commands](#commands) · [Remove integration](#remove-profile-integration) · [Development](#development) · [Credits](#credits) · [Why](#why) · [Disclaimer](#disclaimer)

## Install

Requires Windows 10/11 and [WinGet](https://learn.microsoft.com/windows/package-manager/winget/). Download this repository as a ZIP and extract it, or clone it:

```powershell
git clone https://github.com/suhdoh/shell-control.git
cd shell-control
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\Install.ps1
```

Setup installs Windows Terminal, PowerShell 7, Fastfetch, eza, Gum and Oh My Posh. Start setup from a regular, non-administrator terminal. Only the dependency-installation worker requests UAC elevation when needed; font and configuration workers stay in the original user's context. An already elevated parent process passes its elevation to its children. Package and font tasks show progress inside the menu.

The default destination is `%LOCALAPPDATA%\ShellControl`. Existing PowerShell profiles are backed up. Console sessions and ISE load Shell Control last from their respective current-host profiles. Existing Terminal profiles are retained; three Shell Control profiles are added for PowerShell 7, Windows PowerShell 5.1 and CMD. The dedicated PowerShell profiles start without loading personal or system profiles, then initialize Shell Control directly. This prevents other startup banners and prompt engines from overriding Shell Control in those tabs; the original toolkit files and regular profiles remain available. ISE loads the native prompt and a plain-text Fastfetch greeting, and opens its settings in a graphical menu. ISE stores its font, size and theme separately from Windows Terminal.

Choose a dedicated empty installation directory, or an existing recognized Shell Control installation. Setup rejects drive roots, system directories, populated unrelated folders, source-checkout overlaps and installation paths through junctions or symbolic links.

If both the current-user and machine execution policies prevent local profiles and no organization policy applies, setup enables `RemoteSigned` for the current user. Machine and organization policies are not changed.

Open the **Shell Control · PowerShell 7** profile in Windows Terminal and run:

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

# Repair normal PS5, PS7 and ISE startup; back up and replace old user profile code.
.\Install.ps1 -RepairStartup -Launch

# Custom destination.
.\Install.ps1 -InstallPath D:\ShellControl
```

`-NoProfiles`, `-NoTerminal`, `-NoShortcuts` and `-NoInteractive` are available for selective or unattended configuration. Setup logs and timestamped backups are stored below the installation folder. If a dependency or font installation fails, setup still attempts the independent profile and Terminal configuration, then reports the failed stages. A partial setup is not reported as a completed installation. Re-running setup replaces its own import block rather than appending duplicates. Existing language and prompt preferences are retained. `-RepairStartup` explicitly selects the native prompt and enables Fastfetch. It backs up all five current-user startup profiles for PS5, PS7 and ISE before replacing their previous startup code, disabling old banners and prompt initializers such as BitHawk. It also repairs the ordinary PS5/PS7 Terminal profiles and standard user Start Menu, Desktop and taskbar shortcuts, preserving the selected Terminal appearance. Machine Start Menu shortcuts receive a user-specific counterpart. Script and administrator shortcuts are retained. Existing Windows 11 taskbar pins may cache their old target; unpin and pin the repaired Start Menu entry once if needed. `-NoShortcuts` skips shortcut changes. Direct executable launches still follow the flags supplied by their caller; machine-wide profiles are not edited. It cannot be combined with `-NoTerminal` or `-PreserveTerminalProfiles`. `-Launch` opens the configured Shell Control profile in Windows Terminal after successful setup.

Terminal and profile changes use a temporary file followed by replacement, with unique backups in `.shell-control-backups` beside the edited file. Detected changes since reading cause the save to abort rather than overwrite a newer version. These protections do not provide a transaction or automatic rollback for the entire installation. See [SECURITY.md](SECURITY.md) for the scope and remaining limitations.

## Themes and fonts

Theme families include Amber 340, Osaka Jade, Matrix, Dark Crimson, SynthWave 84, Rosé Pine, Catppuccin and Gruvbox. Rosé Pine, Catppuccin and Gruvbox variants are nested beneath their families. Fonts and prompts use the Terminal palette where supported. Bundled themes remain selectable before their first import; selecting one adds its scheme when needed. Terminal appearance controls require a Windows Terminal tab; starting `pwsh.exe` in the classic Windows Console cannot apply Terminal appearance settings. In ISE, `shell-menu`, `font`, `font-size` and `theme` use the ISE settings and reapply them at startup; CRT is available only in Windows Terminal. A custom pixel shader takes precedence over CRT; disable it in Terminal settings before enabling the CRT effect. When multiple Terminal installations contain the same active profile, select the settings file explicitly with `-TerminalSettingsPath`; setup retains that choice for later sessions and menu workers.

The verified font catalog contains 85 families. The full pack downloads 63 upstream Nerd Font archives; the recommended pack contains Terminess, Gohu, JetBrains Mono, Cascadia Mono, IBM Plex Mono and Meslo. Archives are pinned to Nerd Fonts v3.5.1 and checked against SHA-256 digests. Font licenses are copied with the installed files. Fonts that lack the required symbols or have incompatible character metrics are excluded. No font binaries are redistributed in this repository.

Font choices in the menu are limited to installed families, with an installed/available count and a shortcut to font installation. Successful font registrations are saved as setup progresses and retained across packs, so rerunning setup resumes after a partial failure. A newly installed font may require a new Terminal tab before Windows refreshes its font cache. Natural glyph metrics are used; the retro Terminess preset retains a small spacing adjustment.

Appearance changes stay synchronized between the ordinary and Shell Control profiles for the same PowerShell version, so changing the launch route retains the selected font, size, theme and CRT setting.

The native prompt is the default for fast startup: username, location and time separated by two spaces on the first line, then `❯` on the second line. Oh My Posh is an optional engine using the included minimal configuration. Switch it under **Appearance → Prompt** and open a new tab if your current session retains an earlier prompt hook.

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

This removes the managed PowerShell import blocks and restores repaired shortcuts whose contents still match the generated version. User-edited shortcuts are retained. Earlier profile contents disabled by `-RepairStartup` can be restored from the installer backup folder. Runtime files, fonts, dependencies and Terminal settings are deliberately retained. Restore Terminal settings from the installation's `backups` folder to revert the imported themes and profiles.

The remover only targets imports matching `-InstallPath`. Profile-removal backups and backups from individual menu changes are stored beside their files in `.shell-control-backups`.

## Development

```powershell
powershell.exe -NoProfile -File .\tests\Test-Project.ps1
pwsh -NoProfile -File .\tests\Test-Project.ps1
```

Tests use isolated settings, profile and Windows shortcut fixtures, plus a simulated ISE host; the graphical ISE window still requires an interactive Windows check. They do not install programs, register fonts or change real Terminal settings. A fresh-machine installation is a separate integration check.

## Credits

I do not own the fonts, third-party tools, icons or upstream theme palettes. Fonts are downloaded from **Nerd Fonts**, with the original typeface authors' copyright and licenses preserved. Thanks to those designers, the Nerd Fonts contributors, Charm and all the projects that make this setup possible.

See [third-party credits](THIRD-PARTY.md) for tools, inspiration and themes, and [font credits](FONT-CREDITS.md) for every supported font package and its original notices. Setup installs these credit documents and notices with the configuration. Shell Control's own code is MIT licensed; third-party components retain their own licenses.

## Why

I built this out of laziness: I like good-looking Gum windows and want to customize my terminal however I feel like, without editing config files every time. The defaults just look bad to me. Shell Control puts the things I actually use in one menu, inspired by Charm/Gum and rendered with native PowerShell for Windows.

## Disclaimer

Shell Control is provided as is, without warranty. Use it at your own risk. To the maximum extent permitted by applicable law, the authors and copyright holders are not liable for claims, damages or other losses arising from its use, including data loss or configuration changes. Nothing here excludes liability that cannot legally be excluded. See the [MIT license](LICENSE) for the full terms. Third-party components remain subject to their own licenses and terms.
