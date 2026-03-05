-- lua/wiki/init.lua
local Wiki = {}

Wiki.root = vim.fn.expand("~/brain/notes")
Wiki.extensions = { "md", "typ", "txt" }
Wiki._cache = { files = {}, tick = 0 }

function Wiki.setup(opts)
  opts = opts or {}
  if opts.root then Wiki.root = vim.fn.expand(opts.root) end
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
    require("wiki.gf").gf_create(Wiki)
  end, { desc = "wiki: open/create wikilink/file" })

  vim.api.nvim_create_user_command("WikiCreate", function()
    require("wiki.gf").gf_create(Wiki)
  end, { desc = "Open or create wikilink under cursor" })

  vim.api.nvim_create_user_command("WikiBacklinks", function()
    require("wiki.backlinks").backlinks(Wiki)
  end, { desc = "Show backlinks to current note in quickfix" })

  vim.api.nvim_create_user_command("WikiPanel", function()
    require("wiki.panel").links_panel(Wiki)
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
    require("wiki.gf").gf_create(Wiki)
  end, { desc = "Follow or create wikilink under cursor" })

end

return Wiki
