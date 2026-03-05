-- lua/wiki/panel.lua
local util = require("wiki.util")
local M = {}

local function list_outgoing_links()
  local buf = vim.api.nvim_get_current_buf()
  local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
  local out, seen = {}, {}

  for _, line in ipairs(lines) do
    for inside in line:gmatch("%[%[([^%]]+)%]%]") do
      local tgt = util.normalize_target(inside)
      if tgt ~= "" and not seen[tgt] then
        seen[tgt] = true
        table.insert(out, tgt)
      end
    end
  end

  table.sort(out)
  return out
end

local function list_backlinks(Wiki)
  if vim.fn.executable("rg") ~= 1 then
    return nil, "ripgrep (rg) not found"
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
    return {}, nil
  elseif code ~= 0 then
    return nil, "rg error (exit " .. code .. ")"
  end

  local notes, seen = {}, {}
  local this_note = util.note_name_noext_from_path(vim.fn.expand("%:p"))

  for _, l in ipairs(results) do
    local file = l:match("^(.-):%d+:%d+:")
    if file then
      local src = util.note_name_noext_from_path(file)
      if src ~= this_note and not seen[src] then
        seen[src] = true
        table.insert(notes, src)
      end
    end
  end

  table.sort(notes)
  return notes, nil
end

function M.links_panel(Wiki)
  local cur_name = vim.fn.expand("%:t:r")
  local outgoing = list_outgoing_links()
  local backlinks, err = list_backlinks(Wiki)

  local panel = {}
  table.insert(panel, "Links for: " .. cur_name)
  table.insert(panel, string.rep("─", 40))
  table.insert(panel, "")
  table.insert(panel, "Outgoing:")
  if #outgoing == 0 then
    table.insert(panel, "  (none)")
  else
    for _, n in ipairs(outgoing) do
      table.insert(panel, "  " .. n)
    end
  end

  table.insert(panel, "")
  table.insert(panel, "Backlinks:")
  if err then
    table.insert(panel, "  (error) " .. err)
  elseif #backlinks == 0 then
    table.insert(panel, "  (none)")
  else
    for _, n in ipairs(backlinks) do
      table.insert(panel, "  " .. n)
    end
  end

  local buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_name(buf, "WikiLinks://" .. cur_name)
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, panel)
  vim.bo[buf].buftype = "nofile"
  vim.bo[buf].bufhidden = "wipe"
  vim.bo[buf].swapfile = false
  vim.bo[buf].modifiable = false
  vim.bo[buf].filetype = "wikilinks"

  vim.cmd("vsplit")
  vim.api.nvim_win_set_buf(0, buf)

  vim.keymap.set("n", "<CR>", function()
    local line = vim.fn.getline(".")
    local name = line:match("^%s%s(.+)$")
    if not name or name:match("^%(") then return end
    util.open_note_by_name(Wiki, name)
  end, { buffer = buf, silent = true })

  vim.keymap.set("n", "q", "<cmd>close<cr>", { buffer = buf, silent = true })
end

return M
