# wiki.nvim

A lightweight personal wiki plugin for Neovim. Navigate and create `[[wikilink]]` notes, see backlinks, manage outgoing links, and generate a browser-based graph view — no external dependencies beyond `ripgrep` for backlink search.

## Features

- `[[wikilink]]` navigation and auto-creation via `gf`
- Backlinks via quickfix
- Outgoing + backlink panel in a vertical split
- Wikilink completion (`<C-x><C-u>`) in markdown, typst, and text files
- Browser graph view — Wikipedia-style homepage with D3 force graph
- User commands for all actions
- Configurable root directory and file extensions

## Requirements

- Neovim 0.10+
- [`ripgrep`](https://github.com/BurntSushi/ripgrep) (for backlinks)

## Installation

**vim-plug**
```vim
Plug 'dhayer200/wiki.nvim'
```

**lazy.nvim**
```lua
{ "dhayer200/wiki.nvim" }
```

**vim.pack (Neovim 0.11+)**
```lua
vim.pack.add({ src = "https://github.com/dhayer200/wiki.nvim" })
```

## Setup

```lua
require("wiki").setup({
  root = "~/brain/notes",               -- default
  extensions = { "md", "typ", "txt" },  -- default
})
```

## Commands

| Command | Action |
|---------|--------|
| `:WikiCreate` | Open wikilink under cursor; create file if it doesn't exist |
| `:WikiLink` | Same as `:WikiCreate` |
| `:WikiBacklinks` | Show backlinks to current note in quickfix |
| `:WikiPanel` | Open panel with outgoing links and backlinks |
| `:WikiHelp` | Open wiki helper.md reference in a vertical split |
| `:WikiGraph` | Generate `~/brain/brain.html` and open it in the browser |

## Keymaps

The plugin sets `gf` to open/create wikilinks. Bind the commands however you like:

```lua
vim.keymap.set("n", "<leader>wb", ":WikiBacklinks<cr>")
vim.keymap.set("n", "<leader>ww", ":WikiPanel<cr>")
vim.keymap.set("n", "<leader>hh", ":WikiHelp<cr>")
vim.keymap.set("n", "<leader>wg", ":WikiGraph<cr>")
```

In the links panel: `<CR>` jumps to the note, `q` closes.

Wikilink completion triggers with `<C-x><C-u>` inside any `[[` in markdown, typst, or text files.

## WikiGraph

`:WikiGraph` scans your wiki root, parses all `[[wikilinks]]`, and generates a self-contained `brain.html` that opens in your browser. It shows:

- **Featured** — 5 random notes from your wiki with a blurb
- **Graph** — D3 force-directed graph; nodes sized by link count, click to highlight
- **All Notes** — table of every note and what it links to

Requires an internet connection to load D3.js from CDN.

## License

MIT
