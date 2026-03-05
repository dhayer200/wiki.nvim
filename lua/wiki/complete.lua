-- lua/wiki/complete.lua
local util = require("wiki.util")
local scan = require("wiki.scan")
local M = {}

function M.complete(Wiki)
  return function(findstart, base)
    local line = vim.fn.getline(".")
    local col0 = vim.fn.col(".") - 1 -- 0-based

    if findstart == 1 then
      local start = col0
      while start > 0 do
        local ch = line:sub(start, start)
        if ch:match("[%s%[%]%(%){},;:\"']") then
          break
        end
        start = start - 1
      end
      return start + 1  -- IMPORTANT FIX
    end

    scan.refresh_cache_if_needed(Wiki)

    local inside = util.is_inside_wikilink(line, col0)
    local items = {}
    local base_lc = (base or ""):lower()

    for _, p in ipairs(Wiki._cache.files) do
      local name = util.file_display_name(p)
      if name:lower():find(base_lc, 1, true) then
        local insert = name
        if not inside then
          insert = "[[" .. name .. "]]"
        end

        table.insert(items, {
          word = insert,
          abbr = name,
          menu = "wiki",
          info = scan.file_label(Wiki, p),
          kind = "f",
        })
      end
    end

    return items
  end
end

return M
