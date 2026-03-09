# wiki.nvim

A lightweight personal wiki plugin for Neovim. Navigate `[[wikilink]]` notes, browse outgoing links and backlinks, and explore your knowledge graph in the browser.

## Features

- `gf` opens or creates the wikilink under the cursor
- `<C-x><C-u>` wikilink completion in markdown, typst, and text files
- Outgoing links + backlinks in a vertical split panel
- Browser graph view — D3 force graph with note reader, search, and live reload
- Supports `.md`, `.typ` (Typst), `.tex` (LaTeX), `.txt`, `.rtf`, and `.enex` (Evernote) files

## Requirements

- Neovim 0.10+
- Node.js (for `:WikiGraph`)
- [`ripgrep`](https://github.com/BurntSushi/ripgrep) (for backlink search in panel)

## Installation

**lazy.nvim**
```lua
{ "dhayer200/wiki.nvim" }
```

**vim-plug**
```vim
Plug 'dhayer200/wiki.nvim'
```

**vim.pack (Neovim 0.11+)**
```lua
vim.pack.add({ src = "https://github.com/dhayer200/wiki.nvim" })
```

## Setup

```lua
require("wiki").setup({
  root = "~/notes",                                            -- wiki directory (default: cwd)
  extensions = { "md", "typ", "txt", "rtf", "enex", "tex" }, -- file types to scan
})
```

## Commands

| Command | Action |
|---------|--------|
| `:WikiLink` | If cursor is on `[[target]]` → jump to / create that note. Otherwise → enter insert mode and open wikilink completion picker. |
| `:WikiPanel` | Open a vertical split showing outgoing links and backlinks for the current note. |
| `:WikiGraph` | Start a local server and open the graph view in the browser. |
| `:WikiDaily` | Open (or create) today's daily note (`YYYY-MM-DD.md`). |
| `:WikiIndex` | Generate `index.md` — all notes sorted oldest-first with creation dates. |
| `:WikiCreate <name[.ext]>` | Insert `[[name]]` at cursor and create `wiki_root/name.ext` (defaults to `.md`). |
| `:WikiRename` | Rename current file or the `[[wikilink]]` under cursor; updates all backlinks. |
| `:WikiSearch` | Fuzzy-pick and open any note. |

## Keymaps

`gf` is remapped to follow wikilinks (and create missing files). Suggested bindings:

```lua
vim.keymap.set("n", "<leader>wl", ":WikiLink<cr>")
vim.keymap.set("n", "<leader>wp", ":WikiPanel<cr>")
vim.keymap.set("n", "<leader>wg", ":WikiGraph<cr>")
vim.keymap.set("n", "<leader>wd", ":WikiDaily<cr>")
```

## Wikilink completion

In insert mode, `<C-x><C-u>` completes wikilinks from your wiki root:

- Inside `[[...]]` — inserts the note name only
- Outside — wraps the completion in `[[...]]`

`:WikiLink` from normal mode does the same: if your cursor is already inside `[[...]]`, it jumps to that note; otherwise it triggers the completion picker.

## WikiGraph

`:WikiGraph` scans the wiki root, parses all `[[wikilinks]]`, and opens a self-contained graph in your browser. It includes:

- **Featured** — 5 random notes with a blurb
- **Graph** — D3 force-directed graph; nodes sized by link count; click to open the note reader
- **All Notes** — sortable table of every note and its links
- **Note reader** — renders markdown (with LaTeX via KaTeX), Typst, and LaTeX files; shows outgoing links and backlinks; live-reloads on file save
- **Hover preview** — floating window preview of any `[[wikilink]]` on `CursorHold`

Requires an internet connection to load D3 and KaTeX from CDN.

## License

MIT
