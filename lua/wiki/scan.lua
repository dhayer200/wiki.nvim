-- lua/wiki/scan.lua
local util = require("wiki.util")
local M = {}

local function scan_files(Wiki)
  local root = Wiki.root
  local out = {}

  local has_rg = vim.fn.executable("rg") == 1
  if has_rg then
    local lines = vim.fn.systemlist({ "rg", "--files", root })
    for _, p in ipairs(lines) do
      local ext = p:match("%.([%w_%-]+)$")
      if ext then
        for _, e in ipairs(Wiki.extensions) do
          if ext == e then
            table.insert(out, p)
            break
          end
        end
      end
    end
  else
    for _, e in ipairs(Wiki.extensions) do
      local matches = vim.fn.globpath(root, "**/*." .. e, true, true)
      for _, p in ipairs(matches) do
        table.insert(out, p)
      end
    end
  end

  return out
end

function M.refresh_cache_if_needed(Wiki)
  local now = vim.fn.reltimefloat(vim.fn.reltime())
  if (now - Wiki._cache.tick) < 2.0 and #Wiki._cache.files > 0 then
    return
  end
  Wiki._cache.files = scan_files(Wiki)
  Wiki._cache.tick = now
end

function M.file_label(Wiki, fullpath)
  local name = util.file_display_name(fullpath)
  local rel = vim.fn.fnamemodify(fullpath, ":.")
  return name .. "  (" .. rel .. ")"
end

return M
