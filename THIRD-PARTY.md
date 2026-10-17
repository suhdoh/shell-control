# Third-party components

Shell Control's own scripts and configuration are MIT licensed. I do not own the third-party tools, fonts, icons or upstream theme palettes used here. Their authors retain copyright, and their licenses continue to apply. Project names and trademarks belong to their respective owners; inclusion does not imply endorsement.

## Software and inspiration

| Project / authors | Used for | Upstream license |
| --- | --- | --- |
| [Windows Terminal — Microsoft and contributors](https://github.com/microsoft/terminal) | Terminal profiles, palettes, acrylic transparency and built-in retro effect | [MIT](https://github.com/microsoft/terminal/blob/main/LICENSE) |
| [PowerShell — Microsoft and contributors](https://github.com/PowerShell/PowerShell) | PowerShell 7 runtime | [MIT](https://github.com/PowerShell/PowerShell/blob/master/LICENSE.txt) |
| [WinGet — Microsoft and contributors](https://github.com/microsoft/winget-cli) | Dependency installation | [MIT](https://github.com/microsoft/winget-cli/blob/master/LICENSE) |
| [Fastfetch — Fastfetch contributors](https://github.com/fastfetch-cli/fastfetch) | Hardware discovery and startup system overview; framed report inspired by upstream examples, including TR-100 | [MIT](https://github.com/fastfetch-cli/fastfetch/blob/dev/LICENSE) |
| [eza — eza contributors](https://github.com/eza-community/eza) | Colored file listings | [EUPL-1.2](https://github.com/eza-community/eza/blob/main/LICENSE.txt) |
| [Gum — Charm and contributors](https://github.com/charmbracelet/gum) | Installed companion tool and inspiration for the menu experience | [MIT](https://github.com/charmbracelet/gum/blob/main/LICENSE) |
| [Oh My Posh — Jan De Dobbeleer and contributors](https://github.com/JanDeDobbeleer/oh-my-posh) | Optional prompt engine | [MIT](https://github.com/JanDeDobbeleer/oh-my-posh/blob/main/COPYING) |

The menu itself uses Shell Control's native PowerShell console renderer. It does not embed Gum's renderer. Tools are downloaded through their respective package distributions, not bundled as binaries in this repository. Windows PowerShell 5.1, ISE, CMD and Windows are Microsoft components provided under their applicable Microsoft terms; the PowerShell 7 license does not cover them.

## Fonts and icons

I do not own the fonts. They are obtained from [Nerd Fonts](https://github.com/ryanoasis/nerd-fonts), maintained by Ryan L. McIntyre and contributors, using pinned release v3.5.1 archives. The original typeface designers and icon-set authors retain their rights. Nerd Fonts includes several icon collections; see its [licensing breakdown](https://github.com/ryanoasis/nerd-fonts/blob/v3.5.1/LICENSE) for the individual terms.

See [FONT-CREDITS.md](FONT-CREDITS.md) for every supported font package, its source download and the original copyright/license notices copied from its exact release archive. These notices are also installed alongside the font files. Licenses vary by font; they are not all covered by Shell Control's MIT license. No font binaries are redistributed in this repository. Apple fonts and files from SFWindows are not included or downloaded by this installer.

## Theme color values

- Rosé Pine: [rose-pine/windows-terminal](https://github.com/rose-pine/windows-terminal), Rosé Pine contributors, MIT. Notice included in `assets/licenses/rose-pine.txt`.
- Catppuccin: [catppuccin/windows-terminal](https://github.com/catppuccin/windows-terminal), Catppuccin contributors, MIT. Notice included in `assets/licenses/catppuccin.txt`.
- Gruvbox: [morhetz/gruvbox](https://github.com/morhetz/gruvbox), by Pavel Pertsev; MIT as declared in its `package.json`. Shell Control maps the upstream palette into six Windows Terminal variants. No Vim implementation is copied.
- SynthWave '84: [robb0wen/synthwave-vscode](https://github.com/robb0wen/synthwave-vscode), Robb Owen, MIT. Notice included in `assets/licenses/synthwave84.txt`.
- Osaka Jade: color palette from [Omarchy](https://github.com/basecamp/omarchy), David Heinemeier Hansson and contributors. MIT notice included in `assets/licenses/osaka-jade.txt`.
- Amber 340, Matrix and Dark Crimson: Shell Control palette variants.

Theme names remain associated with their original projects. The Shell Control MIT license does not replace upstream notices.
