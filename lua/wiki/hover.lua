-- lua/wiki/hover.lua
local util = require("wiki.util")
local M = {}

local _win = nil
local _buf = nil

local function close()
  if _win and vim.api.nvim_win_is_valid(_win) then
    vim.api.nvim_win_close(_win, true)
  end
  if _buf and vim.api.nvim_buf_is_valid(_buf) then
    vim.api.nvim_buf_delete(_buf, { force = true })
  end
  _win = nil
  _buf = nil
end

function M.show(Wiki)
  close()

  local line = vim.fn.getline(".")
  local col0 = vim.fn.col(".") - 1
  if not util.is_inside_wikilink(line, col0) then return end

  local target = util.wiki_target_under_cursor()
  if not target then return end

  -- find the file
  local found, found_ext
  for _, ext in ipairs(Wiki.extensions) do
    local c = Wiki.root .. "/" .. target .. "." .. ext
    if vim.fn.filereadable(c) == 1 then found = c; found_ext = ext; break end
  end
  if not found then return end

  local preview_lines = vim.fn.readfile(found, "", 20)
  if #preview_lines == 0 then return end

  -- trim trailing blank lines
  while #preview_lines > 0 and vim.trim(preview_lines[#preview_lines]) == "" do
    table.remove(preview_lines)
  end
  if #preview_lines == 0 then return end

  _buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_lines(_buf, 0, -1, false, preview_lines)
  vim.bo[_buf].filetype = found_ext == "typ" and "typst"
    or found_ext == "tex" and "tex"
    or found_ext == "rtf" and "text"
    or found_ext == "enex" and "xml"
    or found_ext == "txt" and "text"
    or "markdown"
  vim.bo[_buf].modifiable = false

  local width  = math.min(62, vim.o.columns - 6)
  local height = math.min(#preview_lines, 18)

  _win = vim.api.nvim_open_win(_buf, false, {
    relative = "cursor",
    row = 1, col = 0,
    width = width, height = height,
    style = "minimal",
    border = "rounded",
    zindex = 50,
  })
  vim.wo[_win].wrap = true
  vim.wo[_win].conceallevel = 2

  -- close when cursor moves away
  vim.api.nvim_create_autocmd({ "CursorMoved", "CursorMovedI", "InsertEnter", "BufLeave" }, {
    once = true,
    callback = close,
  })
end

function M.setup_autocmd(Wiki)
  vim.api.nvim_create_autocmd("CursorHold", {
    pattern = { "*.md", "*.typ", "*.txt", "*.tex", "*.rtf", "*.enex" },
    callback = function() M.show(Wiki) end,
  })
end

return M
