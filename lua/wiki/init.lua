-- lua/wiki/init.lua
local Wiki = {}

Wiki.root = nil  -- nil = use cwd at invocation time
Wiki._root_explicit = false
Wiki.extensions = { "md", "typ", "txt" }
Wiki._cache = { files = {}, tick = 0 }

local function active_root()
  return Wiki._root_explicit and Wiki.root or vim.fn.getcwd()
end

local function with_root()
  return vim.tbl_extend("force", Wiki, { root = active_root() })
end

function Wiki.setup(opts)
  opts = opts or {}
  if opts.root then
    Wiki.root = vim.fn.expand(opts.root)
    Wiki._root_explicit = true
  end
  if opts.extensions then Wiki.extensions = opts.extensions end

  -- completion func must be a string, so expose globally
  _G.WikiComplete = require("wiki.complete").complete(Wiki)

  vim.api.nvim_create_autocmd("FileType", {
    pattern = { "markdown", "typst", "text" },
    callback = function()
      vim.bo.completefunc = "v:lua.WikiComplete"
    end,
  })

  vim.keymap.set("n", "gf", function()
    require("wiki.gf").gf_create(with_root())
  end, { desc = "wiki: open/create wikilink/file" })

  -- WikiLink: jump if cursor on [[...]], else trigger C-x C-u completion
  vim.api.nvim_create_user_command("WikiLink", function()
    local line = vim.fn.getline(".")
    local col0 = vim.fn.col(".") - 1
    local util = require("wiki.util")
    local target = util.wiki_target_under_cursor()
    if target and util.is_inside_wikilink(line, col0) then
      require("wiki.gf").gf_create(with_root())
    else
      local keys = vim.api.nvim_replace_termcodes("a<C-x><C-u>", true, false, true)
      vim.api.nvim_feedkeys(keys, "n", false)
    end
  end, { desc = "Jump to wikilink under cursor, or trigger completion" })

  vim.api.nvim_create_user_command("WikiPanel", function()
    require("wiki.panel").links_panel(with_root())
  end, { desc = "Open outgoing links + backlinks panel" })

  vim.api.nvim_create_user_command("WikiGraph", function()
    require("wiki.graph").generate(with_root())
  end, { desc = "Generate and open wiki graph in browser" })

  vim.api.nvim_create_user_command("WikiDaily", function()
    local root = active_root()
    local date = os.date("%Y-%m-%d")
    local path = root .. "/" .. date .. ".md"
    vim.fn.mkdir(root, "p")
    if vim.fn.filereadable(path) == 0 then
      vim.fn.writefile({ "# " .. date, "", "" }, path)
    end
    vim.cmd("edit " .. vim.fn.fnameescape(path))
  end, { desc = "Open today's daily note" })

end

return Wiki
