-- lua/wiki/graph.lua
local M = {}

local function read_file(path)
  local f = io.open(path, "r")
  if not f then return "" end
  local content = f:read("*a")
  f:close()
  return content
end

local function get_blurb(path)
  local f = io.open(path, "r")
  if not f then return "" end
  local lines = {}
  for line in f:lines() do
    line = line:gsub("^#+%s*", ""):gsub("^%s+", ""):gsub("%s+$", "")
    if line ~= "" and not line:match("^%-%-%-") and not line:match("^date:") then
      table.insert(lines, line)
      if #lines >= 2 then break end
    end
  end
  f:close()
  return table.concat(lines, " ")
end

local function parse_links(content)
  local links, seen = {}, {}
  for link in content:gmatch("%[%[([^%]|]+)[%]|]") do
    link = link:gsub("^%s+", ""):gsub("%s+$", ""):gsub("%.[%w]+$", "")
    if not seen[link] and link ~= "" then
      seen[link] = true
      table.insert(links, link)
    end
  end
  return links
end

local function scan_notes(root, extensions)
  local notes = {}
  local ext_pat = table.concat(extensions, "|")
  local handle = io.popen(
    string.format('find %s -maxdepth 1 -type f | grep -E "\\.(%s)$"',
      vim.fn.shellescape(root), ext_pat)
  )
  if not handle then return notes end
  for line in handle:lines() do table.insert(notes, line) end
  handle:close()
  return notes
end

local function json_str(s)
  return '"' .. s:gsub('\\', '\\\\'):gsub('"', '\\"'):gsub('\n', ' ') .. '"'
end

function M.generate(Wiki)
  math.randomseed(os.time())
  local notes = scan_notes(Wiki.root, Wiki.extensions)

  local nodes, node_index, edges = {}, {}, {}

  for _, path in ipairs(notes) do
    local name = vim.fn.fnamemodify(path, ":t:r")
    if not node_index[name] then
      node_index[name] = #nodes + 1
      table.insert(nodes, {
        id    = name,
        path  = path,
        blurb = get_blurb(path),
        links = parse_links(read_file(path)),
      })
    end
  end

  for _, node in ipairs(nodes) do
    for _, link in ipairs(node.links) do
      if node_index[link] then
        table.insert(edges, { source = node.id, target = link })
      end
    end
  end

  -- shuffle for featured
  local idx = {}
  for i = 1, #nodes do idx[i] = i end
  for i = #idx, 2, -1 do
    local j = math.random(i)
    idx[i], idx[j] = idx[j], idx[i]
  end

  -- ── HTML pieces ────────────────────────────────────────────────────────────

  local cards = {}
  for i = 1, math.min(5, #nodes) do
    local n = nodes[idx[i]]
    local b = n.blurb ~= "" and n.blurb or "No description yet."
    if #b > 130 then b = b:sub(1, 130) .. "…" end
    b = b:gsub("<", "&lt;"):gsub(">", "&gt;")
    table.insert(cards, string.format(
      '<div class="card" onclick="focusNode(%s)"><div class="card-title">%s</div><div class="card-blurb">%s</div></div>',
      json_str(n.id), n.id, b
    ))
  end

  local rows = {}
  for _, n in ipairs(nodes) do
    local tags = {}
    for _, l in ipairs(n.links) do
      if node_index[l] then
        table.insert(tags, string.format(
          '<span class="tag" onclick="focusNode(%s)">%s</span>', json_str(l), l
        ))
      end
    end
    local links_html = #tags > 0 and table.concat(tags) or '<span class="dim">—</span>'
    table.insert(rows, string.format(
      '<tr id="row-%s"><td class="note-name" onclick="focusNode(%s)">%s</td><td>%s</td></tr>',
      n.id, json_str(n.id), n.id, links_html
    ))
  end

  local nodes_json, edges_json = {}, {}
  for _, n in ipairs(nodes) do
    local b = n.blurb ~= "" and n.blurb or "No description yet."
    if #b > 130 then b = b:sub(1, 130) .. "…" end
    table.insert(nodes_json, string.format('{"id":%s,"blurb":%s}', json_str(n.id), json_str(b)))
  end
  for _, e in ipairs(edges) do
    table.insert(edges_json, string.format('{"source":%s,"target":%s}', json_str(e.source), json_str(e.target)))
  end

  -- ── Template ───────────────────────────────────────────────────────────────
  local html = string.format([[
<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width,initial-scale=1">
<title>Brain</title>
<script src="https://d3js.org/d3.v7.min.js"></script>
<style>
*{box-sizing:border-box;margin:0;padding:0}
body{font-family:'Linux Libertine','Georgia',serif;background:#f8f9fa;color:#202122}

header{background:#fff;border-bottom:1px solid #a2a9b1;padding:14px 28px;display:flex;align-items:baseline;gap:14px}
header h1{font-size:1.6rem;font-weight:normal;letter-spacing:.02em}
header span{color:#54595d;font-size:.9rem}

.section{max-width:1120px;margin:0 auto;padding:28px 24px}
h2{font-size:1rem;font-weight:bold;border-bottom:1px solid #a2a9b1;padding-bottom:5px;margin-bottom:16px;text-transform:uppercase;letter-spacing:.05em;color:#54595d}

.cards{display:grid;grid-template-columns:repeat(auto-fill,minmax(190px,1fr));gap:12px;margin-bottom:36px}
.card{background:#fff;border:1px solid #a2a9b1;border-radius:2px;padding:14px;cursor:pointer;transition:box-shadow .15s}
.card:hover{box-shadow:0 2px 8px rgba(0,0,0,.12)}
.card-title{font-weight:bold;font-size:.95rem;margin-bottom:6px;color:#3366cc}
.card-blurb{font-size:.82rem;color:#54595d;line-height:1.45}

#graph-wrap{background:#fff;border:1px solid #a2a9b1;border-radius:2px;margin-bottom:36px;position:relative;height:520px;overflow:hidden}
#graph-wrap svg{width:100%;height:100%}

.link{stroke:#c8ccd1;stroke-width:1px}
.node circle{stroke:#a2a9b1;stroke-width:1.5px;fill:#eaf3fb;cursor:pointer;transition:fill .2s}
.node circle:hover,.node.focused circle{fill:#3366cc}
.node text{font-size:11px;fill:#202122;pointer-events:none;font-family:sans-serif}

#info{position:absolute;top:12px;right:12px;background:#fff;border:1px solid #a2a9b1;border-radius:2px;padding:12px 14px;max-width:220px;font-size:.85rem;display:none;box-shadow:0 2px 6px rgba(0,0,0,.1)}
#info .t{font-weight:bold;font-size:.95rem;color:#3366cc;margin-bottom:5px}
#info .b{color:#54595d;line-height:1.45}

table{width:100%;border-collapse:collapse;background:#fff;font-size:.88rem}
th{text-align:left;padding:8px 12px;background:#eaecf0;border:1px solid #a2a9b1;font-weight:bold}
td{padding:7px 12px;border-bottom:1px solid #eaecf0;vertical-align:top}
tr:hover td{background:#eaf3fb}
tr.hl td{background:#fef9c3}
.note-name{color:#3366cc;cursor:pointer;font-weight:500;white-space:nowrap}
.tag{display:inline-block;background:#eaecf0;border-radius:2px;padding:1px 7px;margin:2px 2px 2px 0;font-size:.8rem;cursor:pointer;color:#3366cc}
.tag:hover{background:#c8ccd1}
.dim{color:#a2a9b1}
</style>
</head>
<body>
<header><h1>🧠 Brain</h1><span>%d notes &middot; %d connections</span></header>
<div class="section">

<h2>Featured</h2>
<div class="cards">%s</div>

<h2>Graph</h2>
<div id="graph-wrap">
  <div id="info"><div class="t" id="it"></div><div class="b" id="ib"></div></div>
</div>

<h2>All Notes</h2>
<table><thead><tr><th>Note</th><th>Links to</th></tr></thead><tbody>
%s
</tbody></table>
</div>

<script>
const nodes=[%s];
const links=[%s];

const wrap=document.getElementById("graph-wrap");
const W=wrap.clientWidth,H=wrap.clientHeight;
const svg=d3.select("#graph-wrap").append("svg");
const g=svg.append("g");

svg.call(d3.zoom().scaleExtent([.25,5]).on("zoom",e=>g.attr("transform",e.transform)));

const sim=d3.forceSimulation(nodes)
  .force("link",d3.forceLink(links).id(d=>d.id).distance(90))
  .force("charge",d3.forceManyBody().strength(-150))
  .force("center",d3.forceCenter(W/2,H/2))
  .force("collide",d3.forceCollide(20));

const lc={};
links.forEach(l=>{
  const s=l.source.id||l.source,t=l.target.id||l.target;
  lc[s]=(lc[s]||0)+1; lc[t]=(lc[t]||0)+1;
});

const line=g.append("g").selectAll("line").data(links).join("line").attr("class","link");

const drag=d3.drag()
  .on("start",(e,d)=>{if(!e.active)sim.alphaTarget(.3).restart();d.fx=d.x;d.fy=d.y})
  .on("drag", (e,d)=>{d.fx=e.x;d.fy=e.y})
  .on("end",  (e,d)=>{if(!e.active)sim.alphaTarget(0);d.fx=null;d.fy=null});

const node=g.append("g").selectAll("g").data(nodes).join("g").attr("class","node").call(drag);
node.append("circle").attr("r",d=>6+Math.min((lc[d.id]||0)*1.8,12));
node.append("text").attr("dy","0.35em").attr("x",d=>9+Math.min((lc[d.id]||0)*1.8,12)).text(d=>d.id);
node.on("click",(e,d)=>showInfo(d));

sim.on("tick",()=>{
  line.attr("x1",d=>d.source.x).attr("y1",d=>d.source.y)
      .attr("x2",d=>d.target.x).attr("y2",d=>d.target.y);
  node.attr("transform",d=>`translate(${d.x},${d.y})`);
});

function showInfo(d){
  document.getElementById("it").textContent=d.id;
  document.getElementById("ib").textContent=d.blurb;
  document.getElementById("info").style.display="block";
  d3.selectAll(".node").classed("focused",n=>n.id===d.id);
  const row=document.getElementById("row-"+d.id);
  if(row){
    document.querySelectorAll("tr.hl").forEach(r=>r.classList.remove("hl"));
    row.classList.add("hl");
    row.scrollIntoView({behavior:"smooth",block:"nearest"});
  }
}

function focusNode(id){
  const d=nodes.find(n=>n.id===id);
  if(!d)return;
  showInfo(d);
  svg.transition().duration(500).call(
    d3.zoom().scaleExtent([.25,5]).on("zoom",e=>g.attr("transform",e.transform)).transform,
    d3.zoomIdentity.translate(W/2-d.x,H/2-d.y)
  );
}
</script>
</body>
</html>
]], #nodes, #edges,
    table.concat(cards, "\n"),
    table.concat(rows, "\n"),
    table.concat(nodes_json, ","),
    table.concat(edges_json, ",")
  )

  local out = vim.fn.expand("~/brain/brain.html")
  local f = io.open(out, "w")
  if not f then
    vim.notify("WikiGraph: could not write " .. out, vim.log.levels.ERROR)
    return
  end
  f:write(html)
  f:close()
  vim.fn.jobstart({ "open", out }, { detach = true })
  vim.notify("WikiGraph → " .. out)
end

return M
