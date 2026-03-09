-- lua/wiki/rename.lua
local util = require("wiki.util")
local M = {}

function M.rename(Wiki)
  local line = vim.fn.getline(".")
  local col0 = vim.fn.col(".") - 1

  local on_link = util.is_inside_wikilink(line, col0)
  local target  = util.wiki_target_under_cursor()

  -- resolve old file path
  local old_name, old_file
  if on_link and target then
    old_name = target:gsub("|.*$", ""):gsub("^%s+", ""):gsub("%s+$", "")
    for _, ext in ipairs(Wiki.extensions) do
      local c = Wiki.root .. "/" .. old_name .. "." .. ext
      if vim.fn.filereadable(c) == 1 then old_file = c; break end
    end
    if not old_file then
      vim.notify("WikiRename: no file found for [[" .. old_name .. "]]", vim.log.levels.ERROR)
      return
    end
  else
    old_file = vim.fn.expand("%:p")
    old_name = vim.fn.fnamemodify(old_file, ":t:r")
  end

  local prompt = on_link and target
    and ("Rename [[" .. old_name .. "]] to: ")
    or  ("Rename '" .. old_name .. "' to: ")

  vim.ui.input({ prompt = prompt }, function(input)
    if not input or vim.trim(input) == "" then return end
    local new_base = vim.trim(input):gsub("[\r\n]", "")
    vim.schedule(function()

    -- keep same extension if user didn't supply one
    local old_ext = vim.fn.fnamemodify(old_file, ":e")
    local new_filename = new_base:match("%.[%w_%-]+$") and new_base
                         or (new_base .. "." .. old_ext)
    local new_display = vim.fn.fnamemodify(new_filename, ":r")
    local new_file    = Wiki.root .. "/" .. new_filename

    -- rename the file on disk
    local ok, err = os.rename(old_file, new_file)
    if not ok then
      vim.notify("WikiRename: " .. (err or "rename failed"), vim.log.levels.ERROR)
      return
    end

    -- update all [[old_name]] references across the wiki
    local has_rg = vim.fn.executable("rg") == 1
    local files_to_check = {}
    if has_rg then
      files_to_check = vim.fn.systemlist({
        "rg", "--files-with-matches", "--fixed-strings",
        "[[" .. old_name .. "]]", Wiki.root,
      })
    else
      for _, ext in ipairs(Wiki.extensions) do
        local ms = vim.fn.globpath(Wiki.root, "**/*." .. ext, true, true)
        for _, f in ipairs(ms) do table.insert(files_to_check, f) end
      end
    end

    local updated = 0
    -- escape old_name for Lua pattern matching
    local pat = "%[%[" .. old_name:gsub("([%^%$%(%)%%%.%[%]%*%+%-%?%{%}%|\\])", "%%%1") .. "%]%]"
    local rep = "[[" .. new_display .. "]]"
    for _, f in ipairs(files_to_check) do
      local lines = vim.fn.readfile(f)
      local changed = false
      for i, l in ipairs(lines) do
        local new_l = l:gsub(pat, rep)
        if new_l ~= l then lines[i] = new_l; changed = true end
      end
      if changed then
        vim.fn.writefile(lines, f)
        updated = updated + 1
        -- reload buffer if open and unmodified
        local buf = vim.fn.bufnr(f)
        if buf ~= -1 and vim.api.nvim_buf_is_loaded(buf)
            and not vim.bo[buf].modified then
          vim.api.nvim_buf_call(buf, function() vim.cmd({ cmd = "edit", bang = true }) end)
        end
      end
    end

    -- if the renamed file was the current buffer, switch to new path
    local cur = vim.fn.expand("%:p")
    if cur == old_file then
      vim.cmd({ cmd = "edit", args = { new_file } })
    end

    vim.notify(string.format("WikiRename: '%s' → '%s'  (%d file(s) updated)",
      old_name, new_display, updated))
    end) -- vim.schedule
  end)
end

return M
