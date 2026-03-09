-- lua/wiki/init.lua
local Wiki = {}

Wiki.root = nil  -- nil = use cwd at invocation time
Wiki._root_explicit = false
Wiki.extensions = { "md", "typ", "txt", "rtf", "enex", "tex" }
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
    pattern = { "markdown", "typst", "text", "tex" },
    callback = function()
      vim.bo.completefunc = "v:lua.WikiComplete"
    end,
  })

  -- gf: open wikilinks, URLs, or plain files
  vim.keymap.set("n", "gf", function()
    require("wiki.gf").gf_create(with_root())
  end, { desc = "wiki: open/create wikilink, URL, or file" })

  -- WikiLink: jump if on [[...]], else trigger completion
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

  -- WikiCreate filename[.ext] — inserts [[filename]] at cursor and creates the file
  vim.api.nvim_create_user_command("WikiCreate", function(opts_cmd)
    local arg = vim.trim(opts_cmd.args)
    if arg == "" then return end
    local filename = arg:match("^([^%s]+)")
    -- default to .md if no extension given
    if not filename:match("%.[%w_%-]+$") then
      filename = filename .. ".md"
    end
    local display = vim.fn.fnamemodify(filename, ":r")
    local path = active_root() .. "/" .. filename
    require("wiki.util").ensure_file(path)
    local row, col = unpack(vim.api.nvim_win_get_cursor(0))
    local cur_line = vim.api.nvim_get_current_line()
    local insert = "[[" .. display .. "]]"
    local new_line = cur_line:sub(1, col) .. insert .. cur_line:sub(col + 1)
    vim.api.nvim_set_current_line(new_line)
    vim.api.nvim_win_set_cursor(0, { row, col + #insert })
  end, { nargs = 1, desc = "Create file and insert [[name]] at cursor" })

  -- WikiRename — smart rename with backlink update
  vim.api.nvim_create_user_command("WikiRename", function()
    require("wiki.rename").rename(with_root())
  end, { desc = "Rename note and update all backlinks" })

  -- WikiPanel
  vim.api.nvim_create_user_command("WikiPanel", function()
    require("wiki.panel").links_panel(with_root())
  end, { desc = "Open outgoing links + backlinks panel" })

  -- WikiSearch — fuzzy note picker
  vim.api.nvim_create_user_command("WikiSearch", function()
    local W = with_root()
    require("wiki.scan").refresh_cache_if_needed(W)
    local items = {}
    for _, p in ipairs(W._cache.files) do
      local name = vim.fn.fnamemodify(p, ":t:r")
      local stat = vim.loop.fs_stat(p)
      local date = stat and os.date("%Y-%m-%d", stat.mtime.sec) or ""
      table.insert(items, { name = name, date = date, path = p })
    end
    table.sort(items, function(a, b) return a.name < b.name end)
    vim.ui.select(items, {
      prompt = "Wiki notes",
      format_item = function(item)
        return string.format("%-30s  %s", item.name, item.date)
      end,
    }, function(choice)
      if choice then
        vim.cmd({ cmd = "edit", args = { choice.path } })
      end
    end)
  end, { desc = "Fuzzy-pick and open a wiki note" })

  -- WikiIndex
  vim.api.nvim_create_user_command("WikiIndex", function()
    require("wiki.scan").refresh_cache_if_needed(with_root())
    require("wiki.index").generate_index(with_root())
  end, { desc = "Generate index.md sorted by creation date" })

  -- WikiGraph
  vim.api.nvim_create_user_command("WikiGraph", function()
    require("wiki.graph").generate(with_root())
  end, { desc = "Generate and open wiki graph in browser" })

  -- WikiDaily
  vim.api.nvim_create_user_command("WikiDaily", function()
    local root = active_root()
    local date = os.date("%Y-%m-%d")
    local path = root .. "/" .. date .. ".md"
    vim.fn.mkdir(root, "p")
    if vim.fn.filereadable(path) == 0 then
      vim.fn.writefile({ "# " .. date, "", "" }, path)
    end
    vim.cmd({ cmd = "edit", args = { path } })
  end, { desc = "Open today's daily note" })

  -- hover preview on CursorHold
  require("wiki.hover").setup_autocmd(with_root())

end

return Wiki
