# wiki.nvim

A lightweight personal wiki plugin for Neovim. Navigate and create `[[wikilink]]` notes, see backlinks, and manage outgoing links — no external dependencies beyond `ripgrep` for backlink search.

## Features

- `[[wikilink]]` navigation and auto-creation via `gf`
- Backlinks via quickfix
- Outgoing + backlink panel in a vertical split
- Wikilink completion (`<C-x><C-u>`) in markdown, typst, and text files
- Configurable root directory and file extensions

## Requirements

- Neovim 0.10+
- [`ripgrep`](https://github.com/BurntSushi/ripgrep) (for backlinks)

## Installation

With any plugin manager, point it at this repo and call `setup()`.

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
  root = "~/brain/notes",          -- default
  extensions = { "md", "typ", "txt" },  -- default
})
```

## Keymaps

| Key | Action |
|-----|--------|
| `gf` | Open wikilink under cursor; create file if it doesn't exist |
| `<leader>wb` | Show backlinks to current note in quickfix |
| `<leader>ww` | Open panel with outgoing links and backlinks |
| `<C-x><C-u>` | Complete `[[wikilinks]]` (in markdown / typst / text files) |

In the links panel: `<CR>` jumps to the note, `q` closes.

## License

MIT
