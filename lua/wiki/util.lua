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

-- resolve template content for a new note
-- looks for: wiki_root/_templates/<ext>.md, then wiki_root/_template.md
-- replaces {{title}} with the note stem
local function template_lines(wiki_root, path)
  local stem = vim.fn.fnamemodify(path, ":t:r")
  local ext  = vim.fn.fnamemodify(path, ":e")
  local candidates = {
    wiki_root .. "/_templates/" .. ext .. ".md",
    wiki_root .. "/_template.md",
  }
  for _, t in ipairs(candidates) do
    if vim.fn.filereadable(t) == 1 then
      local lines = vim.fn.readfile(t)
      for i, l in ipairs(lines) do
        lines[i] = l:gsub("{{title}}", stem)
      end
      return lines
    end
  end
  -- default: just a heading
  return { "# " .. stem, "", "" }
end

function M.ensure_file(path, wiki_root)
  local dir = vim.fn.fnamemodify(path, ":h")
  vim.fn.mkdir(dir, "p")
  if vim.fn.filereadable(path) == 0 then
    local lines = wiki_root and template_lines(wiki_root, path) or {}
    vim.fn.writefile(lines, path)
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

  M.ensure_file(path, Wiki and Wiki.root)
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
