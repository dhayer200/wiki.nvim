-- lua/wiki/backlinks.lua
local util = require("wiki.util")
local M = {}

function M.backlinks(Wiki)
  if vim.fn.executable("rg") ~= 1 then
    print("backlinks: ripgrep (rg) not found")
    return
  end

  local cur  = vim.fn.expand("%:t")
  local stem = vim.fn.expand("%:t:r")

  local patterns = {
    "\\[\\[" .. util.rg_escape(cur)  .. "\\]\\]",
    "\\[\\[" .. util.rg_escape(stem) .. "\\]\\]",
  }

  local args = { "rg", "--vimgrep", "--no-heading", "-S" }
  for _, p in ipairs(patterns) do
    table.insert(args, "-e")
    table.insert(args, p)
  end
  table.insert(args, Wiki.root)

  local results = vim.fn.systemlist(args)
  local code = vim.v.shell_error

  if code == 1 or #results == 0 then
    print("no backlinks found")
    return
  elseif code ~= 0 then
    print("backlinks: rg error (exit " .. code .. ")")
    return
  end

  vim.fn.setqflist({}, "r", {
    title = "Backlinks → " .. cur,
    lines = results,
  })
  vim.cmd("copen")
end

return M
