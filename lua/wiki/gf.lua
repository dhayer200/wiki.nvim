-- lua/wiki/gf.lua
local util = require("wiki.util")
local M = {}

function M.gf_create(Wiki)
  local target = util.wiki_target_under_cursor()
  if not target then
    print("gf: no target under cursor")
    return
  end

  -- normalize [[note|alias]] etc for file creation
  local name = target:gsub("|.*$", ""):gsub("^%s+", ""):gsub("%s+$", "")

  -- If no extension, default to .md
  if not name:match("%.[%w_%-]+$") then
    name = name .. ".md"
  end

  local path = name
  if not path:match("^/") then
    path = Wiki.root .. "/" .. path
  end

  util.ensure_file(path)
  vim.cmd("edit " .. vim.fn.fnameescape(path))
end

return M
