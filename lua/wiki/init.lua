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

  vim.api.nvim_create_user_command("WikiCreate", function()
    require("wiki.gf").gf_create(with_root())
  end, { desc = "Open or create wikilink under cursor" })

  vim.api.nvim_create_user_command("WikiBacklinks", function()
    require("wiki.backlinks").backlinks(with_root())
  end, { desc = "Show backlinks to current note in quickfix" })

  vim.api.nvim_create_user_command("WikiPanel", function()
    require("wiki.panel").links_panel(with_root())
  end, { desc = "Open outgoing links + backlinks panel" })

  vim.api.nvim_create_user_command("WikiHelp", function()
    local path = vim.fn.stdpath("config") .. "/lua/wiki/helper.md"
    vim.cmd("vsplit " .. vim.fn.fnameescape(path))
    vim.bo.readonly = true
    vim.bo.modifiable = false
    vim.bo.bufhidden = "wipe"
    vim.bo.filetype = "markdown"
  end, { desc = "Open wiki helper.md reference" })

  vim.api.nvim_create_user_command("WikiLink", function()
    require("wiki.gf").gf_create(with_root())
  end, { desc = "Follow or create wikilink under cursor" })

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
