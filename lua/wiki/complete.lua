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
      return start
    end

    scan.refresh_cache_if_needed(Wiki)

    local inside = util.is_inside_wikilink(line, col0)
    local items = {}
    local base_lc = (base or ""):lower()

    for _, p in ipairs(Wiki._cache.files) do
      local name = util.file_display_name(p)        -- e.g. "note.md"
      local stem = vim.fn.fnamemodify(p, ":t:r")    -- e.g. "note"
      if stem:lower():find(base_lc, 1, true) then
        local insert = inside and stem or ("[[" .. stem .. "]]")
        local blurb = ""
        local ok, ls = pcall(vim.fn.readfile, p, "", 6)
        if ok then
          for _, l in ipairs(ls) do
            local t = l:gsub("^#+%s*", ""):gsub("^=%+%s*", ""):gsub("^%s+", ""):gsub("%s+$", "")
            if t ~= "" then blurb = t; break end
          end
        end
        table.insert(items, {
          word = insert,
          abbr = stem,
          menu = blurb,
          kind = "f",
        })
      end
    end

    -- if nothing matched the typed text, offer to create a new note
    if #items == 0 and base_lc ~= "" then
      local insert = inside and base or ("[[" .. base .. "]]")
      table.insert(items, {
        word = insert,
        abbr = base .. "  [new]",
        menu = "wiki:new",
        kind = "f",
      })
    end

    return items
  end
end

return M
