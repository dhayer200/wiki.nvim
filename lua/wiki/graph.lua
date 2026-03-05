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
    if line ~= "" and not line:match("^%-%-%-") and not line:match("^date:") and not line:match("^#import") then
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

local function jstr(s)
  return '"' .. s:gsub('\\', '\\\\'):gsub('"', '\\"'):gsub('\n', ' '):gsub('\r', '') .. '"'
end

local function hesc(s)
  return s:gsub('&', '&amp;'):gsub('<', '&lt;'):gsub('>', '&gt;'):gsub('"', '&quot;')
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
    table.insert(cards, string.format(
      '<div class="card" onclick="focusNode(%s)"><div class="card-title">%s</div><div class="card-blurb">%s</div></div>',
      jstr(n.id), hesc(n.id), hesc(b)
    ))
  end

  local rows = {}
  for _, n in ipairs(nodes) do
    local tags = {}
    for _, l in ipairs(n.links) do
      if node_index[l] then
        table.insert(tags, string.format(
          '<span class="tag" onclick="focusNode(%s)">%s</span>', jstr(l), hesc(l)
        ))
      end
    end
    local links_html = #tags > 0 and table.concat(tags) or '<span class="dim">—</span>'
    table.insert(rows, string.format(
      '<tr id="row-%s"><td class="note-name" onclick="focusNode(%s)">%s</td><td>%s</td></tr>',
      hesc(n.id), jstr(n.id), hesc(n.id), links_html
    ))
  end

  local nodes_json, edges_json = {}, {}
  for _, n in ipairs(nodes) do
    local b = n.blurb ~= "" and n.blurb or "No description yet."
    if #b > 130 then b = b:sub(1, 130) .. "…" end
    table.insert(nodes_json, string.format('{"id":%s,"blurb":%s}', jstr(n.id), jstr(b)))
  end
  for _, e in ipairs(edges) do
    table.insert(edges_json, string.format('{"source":%s,"target":%s}', jstr(e.source), jstr(e.target)))
  end

  -- ── Template ───────────────────────────────────────────────────────────────
  -- Note: %% = literal % in string.format

  local html = [[<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width,initial-scale=1">
<title>Brain</title>
<style>
*{box-sizing:border-box;margin:0;padding:0}
body{font-family:'Linux Libertine','Georgia',serif;background:#f8f9fa;color:#202122}
header{background:#fff;border-bottom:1px solid #a2a9b1;padding:14px 28px;display:flex;align-items:baseline;gap:14px}
header h1{font-size:1.6rem;font-weight:normal;letter-spacing:.02em}
header span{color:#54595d;font-size:.9rem}
.section{max-width:1120px;margin:0 auto;padding:28px 24px}
h2{font-size:.85rem;font-weight:bold;border-bottom:1px solid #a2a9b1;padding-bottom:5px;margin-bottom:16px;text-transform:uppercase;letter-spacing:.07em;color:#54595d}
.cards{display:grid;grid-template-columns:repeat(auto-fill,minmax(190px,1fr));gap:12px;margin-bottom:36px}
.card{background:#fff;border:1px solid #a2a9b1;border-radius:2px;padding:14px;cursor:pointer;transition:box-shadow .15s}
.card:hover{box-shadow:0 2px 8px rgba(0,0,0,.12)}
.card-title{font-weight:bold;font-size:.95rem;margin-bottom:6px;color:#3366cc}
.card-blurb{font-size:.82rem;color:#54595d;line-height:1.45}
#graph-wrap{background:#fff;border:1px solid #a2a9b1;border-radius:2px;margin-bottom:36px;position:relative;height:520px;overflow:hidden;cursor:grab}
#graph-wrap.panning{cursor:grabbing}
#graph-wrap svg{width:100%;height:100%;display:block}
.link{stroke:#c8ccd1;stroke-width:1px}
.node circle{stroke:#a2a9b1;stroke-width:1.5px;fill:#eaf3fb;cursor:pointer;transition:fill .15s}
.node:hover circle,.node.focused circle{fill:#3366cc}
.node text{font-size:11px;fill:#202122;pointer-events:none;font-family:sans-serif}
#info{position:absolute;top:12px;right:12px;background:#fff;border:1px solid #a2a9b1;border-radius:2px;padding:12px 14px;max-width:220px;font-size:.85rem;display:none;box-shadow:0 2px 6px rgba(0,0,0,.1);pointer-events:none}
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
<header>
  <h1>&#x1F9E0; Brain</h1>
  <span>]] .. #nodes .. [[ notes &middot; ]] .. #edges .. [[ connections</span>
</header>
<div class="section">
  <h2>Featured</h2>
  <div class="cards">]] .. table.concat(cards, "\n") .. [[</div>
  <h2>Graph</h2>
  <div id="graph-wrap">
    <svg id="svg"><g id="g"><g id="links"></g><g id="nodes"></g></g></svg>
    <div id="info"><div class="t" id="it"></div><div class="b" id="ib"></div></div>
  </div>
  <h2>All Notes</h2>
  <table><thead><tr><th>Note</th><th>Links to</th></tr></thead>
  <tbody>]] .. table.concat(rows, "\n") .. [[</tbody></table>
</div>
<script>
const rawNodes = []] .. table.concat(nodes_json, ",") .. [[];
const rawEdges = []] .. table.concat(edges_json, ",") .. [[];

// ── SVG setup ──────────────────────────────────────────────────────────────
const wrap = document.getElementById('graph-wrap');
const svg  = document.getElementById('svg');
const g    = document.getElementById('g');
const linksG = document.getElementById('links');
const nodesG = document.getElementById('nodes');
const NS = 'http://www.w3.org/2000/svg';
const W = svg.clientWidth, H = svg.clientHeight;

// ── Zoom / pan state ───────────────────────────────────────────────────────
let tx = 0, ty = 0, sc = 1;
function applyTransform() {
  g.setAttribute('transform', `translate(${tx},${ty}) scale(${sc})`);
}

svg.addEventListener('wheel', e => {
  e.preventDefault();
  const factor = e.deltaY > 0 ? 0.9 : 1.1;
  const rect = svg.getBoundingClientRect();
  const mx = e.clientX - rect.left;
  const my = e.clientY - rect.top;
  tx = mx - (mx - tx) * factor;
  ty = my - (my - ty) * factor;
  sc = Math.min(5, Math.max(0.2, sc * factor));
  applyTransform();
}, { passive: false });

let panning = false, panStart = {};
svg.addEventListener('mousedown', e => {
  if (e.target === svg || e.target === g ||
      e.target.closest('#links') ||
      (e.target.closest('#nodes') && e.target.tagName === 'text')) {
    panning = true;
    wrap.classList.add('panning');
    panStart = { x: e.clientX - tx, y: e.clientY - ty };
  }
});
window.addEventListener('mousemove', e => {
  if (!panning) return;
  tx = e.clientX - panStart.x;
  ty = e.clientY - panStart.y;
  applyTransform();
});
window.addEventListener('mouseup', () => {
  panning = false;
  wrap.classList.remove('panning');
});

// ── Build node/link data ───────────────────────────────────────────────────
const nodes = rawNodes.map(n => ({
  ...n,
  x: W/2 + (Math.random()-0.5)*200,
  y: H/2 + (Math.random()-0.5)*200,
  vx: 0, vy: 0, fx: null, fy: null
}));
const nodeById = Object.fromEntries(nodes.map(n => [n.id, n]));
const links = rawEdges
  .map(e => ({ source: nodeById[e.source], target: nodeById[e.target] }))
  .filter(e => e.source && e.target);

const lc = {};
links.forEach(l => {
  lc[l.source.id] = (lc[l.source.id]||0) + 1;
  lc[l.target.id] = (lc[l.target.id]||0) + 1;
});

// ── Create SVG elements ────────────────────────────────────────────────────
const lineEls = links.map(() => {
  const el = document.createElementNS(NS, 'line');
  el.setAttribute('class', 'link');
  linksG.appendChild(el);
  return el;
});

const nodeEls = nodes.map(n => {
  const grp = document.createElementNS(NS, 'g');
  grp.setAttribute('class', 'node');
  grp.id = 'n-' + n.id;

  const r = 6 + Math.min((lc[n.id]||0) * 1.8, 12);
  const circle = document.createElementNS(NS, 'circle');
  circle.setAttribute('r', r);

  const text = document.createElementNS(NS, 'text');
  text.setAttribute('dy', '0.35em');
  text.setAttribute('x', r + 3);
  text.textContent = n.id;

  grp.appendChild(circle);
  grp.appendChild(text);
  nodesG.appendChild(grp);
  grp.addEventListener('click', () => showInfo(n));

  // drag
  grp.addEventListener('mousedown', e => {
    e.stopPropagation();
    const rect = svg.getBoundingClientRect();
    n.fx = n.x; n.fy = n.y;
    reheat();
    const onMove = e2 => {
      n.fx = (e2.clientX - rect.left - tx) / sc;
      n.fy = (e2.clientY - rect.top  - ty) / sc;
    };
    const onUp = () => {
      n.fx = null; n.fy = null;
      window.removeEventListener('mousemove', onMove);
      window.removeEventListener('mouseup', onUp);
    };
    window.addEventListener('mousemove', onMove);
    window.addEventListener('mouseup', onUp);
  });

  return grp;
});

// ── Force simulation ───────────────────────────────────────────────────────
let alpha = 1;
const ALPHA_DECAY   = 0.022;
const ALPHA_MIN     = 0.001;
const VEL_DECAY     = 0.4;
const LINK_DIST     = 90;
const REPULSE       = -160;
const COLLIDE_R     = 22;

function simTick() {
  if (alpha < ALPHA_MIN) return;
  alpha *= (1 - ALPHA_DECAY);

  // center gravity
  nodes.forEach(n => {
    if (n.fx == null) n.vx += (W/2 - n.x) * 0.02 * alpha;
    if (n.fy == null) n.vy += (H/2 - n.y) * 0.02 * alpha;
  });

  // repulsion (n²; fine for personal wikis)
  for (let i = 0; i < nodes.length; i++) {
    for (let j = i + 1; j < nodes.length; j++) {
      const a = nodes[i], b = nodes[j];
      const dx = b.x - a.x, dy = b.y - a.y;
      const d  = Math.sqrt(dx*dx + dy*dy) || 1;
      const f  = REPULSE / (d * d) * alpha;
      if (a.fx == null) { a.vx -= f * dx/d; a.vy -= f * dy/d; }
      if (b.fx == null) { b.vx += f * dx/d; b.vy += f * dy/d; }
    }
  }

  // spring attraction along links
  links.forEach(l => {
    const dx = l.target.x - l.source.x;
    const dy = l.target.y - l.source.y;
    const d  = Math.sqrt(dx*dx + dy*dy) || 1;
    const f  = (d - LINK_DIST) / d * 0.3 * alpha;
    if (l.source.fx == null) { l.source.vx += f*dx; l.source.vy += f*dy; }
    if (l.target.fx == null) { l.target.vx -= f*dx; l.target.vy -= f*dy; }
  });

  // collision
  for (let i = 0; i < nodes.length; i++) {
    for (let j = i + 1; j < nodes.length; j++) {
      const a = nodes[i], b = nodes[j];
      const dx = b.x - a.x, dy = b.y - a.y;
      const d  = Math.sqrt(dx*dx + dy*dy) || 1;
      if (d < COLLIDE_R) {
        const ov = (COLLIDE_R - d) / d * 0.5;
        if (a.fx == null) { a.vx -= dx*ov; a.vy -= dy*ov; }
        if (b.fx == null) { b.vx += dx*ov; b.vy += dy*ov; }
      }
    }
  }

  // integrate
  nodes.forEach(n => {
    if (n.fx != null) { n.x = n.fx; n.vx = 0; }
    else { n.vx *= (1 - VEL_DECAY); n.x += n.vx; }
    if (n.fy != null) { n.y = n.fy; n.vy = 0; }
    else { n.vy *= (1 - VEL_DECAY); n.y += n.vy; }
  });

  // render
  lineEls.forEach((el, i) => {
    el.setAttribute('x1', links[i].source.x);
    el.setAttribute('y1', links[i].source.y);
    el.setAttribute('x2', links[i].target.x);
    el.setAttribute('y2', links[i].target.y);
  });
  nodeEls.forEach((el, i) => {
    el.setAttribute('transform', `translate(${nodes[i].x},${nodes[i].y})`);
  });

  requestAnimationFrame(simTick);
}

function reheat() { alpha = 0.3; requestAnimationFrame(simTick); }
requestAnimationFrame(simTick);

// ── Info panel + focus ─────────────────────────────────────────────────────
function showInfo(n) {
  document.getElementById('it').textContent = n.id;
  document.getElementById('ib').textContent = n.blurb;
  document.getElementById('info').style.display = 'block';
  document.querySelectorAll('.node.focused').forEach(el => el.classList.remove('focused'));
  const el = document.getElementById('n-' + n.id);
  if (el) el.classList.add('focused');
  const row = document.getElementById('row-' + n.id);
  if (row) {
    document.querySelectorAll('tr.hl').forEach(r => r.classList.remove('hl'));
    row.classList.add('hl');
    row.scrollIntoView({ behavior: 'smooth', block: 'nearest' });
  }
}

function focusNode(id) {
  const n = nodes.find(n => n.id === id);
  if (!n) return;
  showInfo(n);
  tx = W/2 - n.x * sc;
  ty = H/2 - n.y * sc;
  applyTransform();
}
</script>
</body>
</html>]]

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
