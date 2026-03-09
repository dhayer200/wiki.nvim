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

  -- when a wiki:new item is confirmed, create the file and open it
  vim.api.nvim_create_autocmd("CompleteDone", {
    pattern = { "*.md", "*.typ", "*.txt", "*.tex", "*.rtf", "*.enex" },
    callback = function()
      local item = vim.v.completed_item
      if not item or item.menu ~= "wiki:new" then return end
      local word = item.word or ""
      local stem = word:match("%[%[(.-)%]%]") or word
      if stem == "" then return end
      vim.schedule(function()
        local path = active_root() .. "/" .. stem .. ".md"
        require("wiki.util").ensure_file(path)
      end)
    end,
  })

  -- gf: open wikilinks, URLs, or plain files
  vim.keymap.set("n", "gf", function()
    require("wiki.gf").gf_create(with_root())
  end, { desc = "wiki: open/create wikilink, URL, or file" })

  -- WikiLink: with arg → create file + insert [[name]]; without arg → jump or complete
  vim.api.nvim_create_user_command("WikiLink", function(opts_cmd)
    local arg = vim.trim(opts_cmd.args)
    if arg ~= "" then
      -- :WikiLink filename[.ext] — create file and insert [[name]] at cursor
      local filename = arg:match("^([^%s]+)")
      if not filename:match("%.[%w_%-]+$") then filename = filename .. ".md" end
      local display = vim.fn.fnamemodify(filename, ":r")
      local path = active_root() .. "/" .. filename
      require("wiki.util").ensure_file(path)
      local row, col = unpack(vim.api.nvim_win_get_cursor(0))
      local cur_line = vim.api.nvim_get_current_line()
      local insert = "[[" .. display .. "]]"
      vim.api.nvim_set_current_line(cur_line:sub(1, col) .. insert .. cur_line:sub(col + 1))
      vim.api.nvim_win_set_cursor(0, { row, col + #insert })
    else
      -- :WikiLink (no arg) — jump if on [[...]], else trigger completion
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
    end
  end, { nargs = "?", desc = "Jump/complete wikilink, or :WikiLink name[.ext] to create" })

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

  -- WikiHelp — floating window showing all commands
  vim.api.nvim_create_user_command("WikiHelp", function()
    local lines = {
      "  wiki.nvim help                              q / <Esc> to close  ",
      "  ─────────────────────────────────────────────────────────────── ",
      "                                                                   ",
      "  NORMAL MODE                                                      ",
      "  gf                 Open wikilink under cursor; follow URL;       ",
      "                     create file if it doesn't exist               ",
      "                                                                   ",
      "  INSERT MODE                                                      ",
      "  <C-x><C-u>         Open wiki completion picker                   ",
      "  <C-n> / <C-p>      Next / previous item in picker                ",
      "  <CR>               Confirm selected item                         ",
      "  <C-e>              Cancel completion                             ",
      "  <C-u>              Revert to original typed text                 ",
      "                                                                   ",
      "  COMMANDS                                                         ",
      "  :WikiLink           Jump to [[link]] under cursor, or open       ",
      "                      completion picker                            ",
      "  :WikiLink name      Create name.md and insert [[name]] at cursor ",
      "  :WikiLink name.ext  Create name.ext and insert [[name]] at cursor",
      "  :WikiRename         Rename current note or [[link]] under cursor;",
      "                      updates all backlinks across the wiki        ",
      "  :WikiPanel          Open outgoing links + backlinks side panel   ",
      "  :WikiSearch         Fuzzy-pick and open any note                 ",
      "  :WikiIndex          Generate index.md sorted by creation date    ",
      "  :WikiGraph          Open interactive graph view in browser       ",
      "  :WikiDaily          Open / create today's daily note             ",
      "  :WikiHelp           Show this help window                        ",
      "                                                                   ",
    }
    local width = 67
    local height = #lines
    local buf = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
    vim.bo[buf].modifiable = false
    vim.bo[buf].filetype = "text"
    local win = vim.api.nvim_open_win(buf, true, {
      relative = "editor",
      row = math.floor((vim.o.lines - height) / 2),
      col = math.floor((vim.o.columns - width) / 2),
      width = width,
      height = height,
      style = "minimal",
      border = "rounded",
    })
    vim.wo[win].wrap = false
    vim.wo[win].cursorline = true
    for _, key in ipairs({ "q", "<Esc>" }) do
      vim.keymap.set("n", key, function()
        vim.api.nvim_win_close(win, true)
        vim.api.nvim_buf_delete(buf, { force = true })
      end, { buffer = buf, nowait = true })
    end
  end, { desc = "Show wiki.nvim command reference" })

  -- hover preview on CursorHold
  require("wiki.hover").setup_autocmd(with_root())

end

return Wiki
