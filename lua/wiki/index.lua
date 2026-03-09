-- lua/wiki/index.lua
local M = {}

function M.generate_index(Wiki)
  local root = Wiki.root
  local entries = {}

  for _, p in ipairs(Wiki._cache.files) do
    local name = vim.fn.fnamemodify(p, ":t:r")
    if name == "index" then goto continue end

    local stat = vim.loop.fs_stat(p)
    local ts = stat and (stat.birthtime and stat.birthtime.sec or stat.mtime.sec) or 0
    table.insert(entries, { name = name, ts = ts, path = p })

    ::continue::
  end

  -- sort oldest first
  table.sort(entries, function(a, b) return a.ts < b.ts end)

  -- build lines
  local lines = { "# Index", "" }
  for _, e in ipairs(entries) do
    local date = os.date("%Y-%m-%d", e.ts)
    local link = string.format("- [[%s]]", e.name)
    -- pad link to column 40, then append date
    local pad = math.max(1, 40 - #link)
    table.insert(lines, link .. string.rep(" ", pad) .. date)
  end
  table.insert(lines, "")

  local out = root .. "/index.md"
  vim.fn.writefile(lines, out)
  vim.cmd({ cmd = "edit", args = { out } })
  vim.notify(string.format("WikiIndex: %d notes → index.md", #entries))
end

return M
