-- lua/wiki/util.lua
local M = {}

function M.is_inside_wikilink(line, col0)
  local left = line:sub(1, col0)
  local open_pos = left:find("%[%[[^%]]*$")
  return open_pos ~= nil
end

function M.file_display_name(fullpath)
  return vim.fn.fnamemodify(fullpath, ":t")
end

function M.note_name_noext_from_path(p)
  return vim.fn.fnamemodify(p, ":t:r")
end

function M.normalize_target(s)
  s = s:gsub("^%s+", ""):gsub("%s+$", "")
  s = s:gsub("|.*$", "")           -- drop alias
  s = s:gsub("^%./", "")
  s = s:gsub("%.[%w_%-]+$", "")    -- drop extension
  return s
end

function M.rg_escape(s)
  return (s:gsub("([%^%$%(%)%%%.%[%]%*%+%-%?%{%}%|\\])", "\\%1"))
end

function M.ensure_file(path)
  local dir = vim.fn.fnamemodify(path, ":h")
  vim.fn.mkdir(dir, "p")
  if vim.fn.filereadable(path) == 0 then
    vim.fn.writefile({}, path)
  end
end

function M.ensure_note_path(Wiki, name)
  local filename = name
  if not filename:match("%.[%w_%-]+$") then
    filename = filename .. ".md"
  end

  local path = filename
  if not path:match("^/") then
    path = Wiki.root .. "/" .. path
  end

  M.ensure_file(path)
  return path
end

function M.open_note_by_name(Wiki, name)
  local path = M.ensure_note_path(Wiki, name)
  vim.cmd({ cmd = "edit", args = { path } })
end

function M.wiki_target_under_cursor()
  local line = vim.fn.getline(".")
  local col = vim.fn.col(".") -- 1-based

  -- prefer [[...]] when cursor is in/near it
  local left = line:sub(1, col)
  local open_pos = left:find("%[%[[^%]]*$")
  if open_pos then
    local close_pos = line:find("%]%]", open_pos)
    if close_pos then
      local inside = line:sub(open_pos + 2, close_pos - 1)
      inside = inside:gsub("^%s+", ""):gsub("%s+$", "")
      if inside ~= "" then return inside end
    end
  end

  local cfile = vim.fn.expand("<cfile>")
  if cfile ~= "" then return cfile end

  return nil
end

return M
