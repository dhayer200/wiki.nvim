-- lua/wiki/gf.lua
local util = require("wiki.util")
local M = {}

function M.gf_create(Wiki)
  local target = util.wiki_target_under_cursor()
  if not target then
    print("gf: no target under cursor")
    return
  end

  -- open URLs in the browser
  if target:match("^https?://") or target:match("^[a-z][a-z+%-%.]*://") then
    local opener = vim.fn.has("mac") == 1 and "open"
      or vim.fn.has("win32") == 1 and "explorer"
      or "xdg-open"
    vim.fn.jobstart({ opener, target }, { detach = true })
    return
  end

  -- normalize [[note|alias]] etc for file creation
  local name = target:gsub("|.*$", ""):gsub("^%s+", ""):gsub("%s+$", "")

  -- If no extension, search for an existing file with any configured extension
  if not name:match("%.[%w_%-]+$") then
    local found
    for _, ext in ipairs(Wiki.extensions) do
      local candidate = Wiki.root .. "/" .. name .. "." .. ext
      if vim.fn.filereadable(candidate) == 1 then
        found = candidate
        break
      end
    end
    name = found and vim.fn.fnamemodify(found, ":t") or (name .. ".md")
  end

  local path = name
  if not path:match("^/") then
    path = Wiki.root .. "/" .. path
  end

  util.ensure_file(path, Wiki.root)
  vim.cmd({ cmd = "edit", args = { path } })
end

return M
