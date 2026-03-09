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

  -- capture plugin root at setup time for WikiHelp
  local _plugin_root = vim.fn.fnamemodify(
    debug.getinfo(1, "S").source:sub(2), ":h:h:h")

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

  -- WikiCreate text.filetype — inserts [[text]] at cursor and creates the file
  vim.api.nvim_create_user_command("WikiCreate", function(opts_cmd)
    local arg = vim.trim(opts_cmd.args)
    if arg == "" then
      -- fallback: jump/create under cursor
      require("wiki.gf").gf_create(with_root())
      return
    end
    local filename = arg:match("^([^%s]+)")
    if not filename then return end
    local display = vim.fn.fnamemodify(filename, ":r")  -- strip extension for [[...]]
    local path = active_root() .. "/" .. filename
    require("wiki.util").ensure_file(path)
    -- insert [[display]] at cursor position
    local row, col = unpack(vim.api.nvim_win_get_cursor(0))
    local cur_line = vim.api.nvim_get_current_line()
    local insert = "[[" .. display .. "]]"
    local new_line = cur_line:sub(1, col) .. insert .. cur_line:sub(col + 1)
    vim.api.nvim_set_current_line(new_line)
    vim.api.nvim_win_set_cursor(0, { row, col + #insert })
  end, { nargs = "?", desc = "Insert [[text]] at cursor and create wiki_root/text.filetype" })

  vim.api.nvim_create_user_command("WikiPanel", function()
    require("wiki.panel").links_panel(with_root())
  end, { desc = "Open outgoing links + backlinks panel" })

  vim.api.nvim_create_user_command("WikiHelp", function()
    local path = _plugin_root .. "/README.md"
    vim.cmd("vsplit " .. vim.fn.fnameescape(path))
    vim.bo.readonly = true
    vim.bo.modifiable = false
    vim.bo.bufhidden = "wipe"
    vim.bo.filetype = "markdown"
  end, { desc = "Open wiki README reference" })

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
