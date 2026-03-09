-- lua/wiki/graph.lua
local M = {}

local _job_id = nil
local PORT = 5757

local function server_script()
  local src = debug.getinfo(1, "S").source:sub(2)
  return vim.fn.fnamemodify(src, ":h") .. "/server.js"
end

function M.generate(Wiki)
  local node_bin = vim.fn.executable("node") == 1 and "node"
    or vim.fn.executable("nodejs") == 1 and "nodejs"
    or nil
  if not node_bin then
    vim.notify("WikiGraph: node/nodejs not found in PATH", vim.log.levels.ERROR)
    return
  end

  -- kill any existing server
  if _job_id then
    vim.fn.jobstop(_job_id)
    _job_id = nil
  end

  local script = server_script()
  if vim.fn.filereadable(script) == 0 then
    vim.notify("WikiGraph: server.js not found at " .. script, vim.log.levels.ERROR)
    return
  end

  local root = Wiki.root

  _job_id = vim.fn.jobstart(
    { node_bin, script, root, tostring(PORT) },
    {
      on_stdout = function(_, data)
        for _, line in ipairs(data) do
          local file = line:match("^OPEN:(.+)$")
          if file then
            vim.schedule(function()
              local full = root .. "/" .. file
              vim.cmd({ cmd = "edit", args = { full } })
            end)
          end
        end
      end,
      on_stderr = function(_, _) end,
      on_exit = function() _job_id = nil end,
    }
  )

  -- give server a moment to bind, then open browser
  local url = "http://127.0.0.1:" .. PORT
  vim.defer_fn(function()
    local opener
    if vim.fn.has("mac") == 1 then
      opener = "open"
    elseif vim.fn.has("win32") == 1 then
      opener = "explorer"
    else
      opener = "xdg-open"
    end
    vim.fn.jobstart({ opener, url }, { detach = true })
    vim.notify("WikiGraph → " .. url)
  end, 200)
end

return M
