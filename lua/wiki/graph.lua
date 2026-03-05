-- lua/wiki/graph.lua
local M = {}

local function read_file(path)
  local f = io.open(path, "r")
  if not f then return "" end
  local content = f:read("*a")
  f:close()
  return content
end

local function get_blurb(content)
  for line in content:gmatch("[^\n]+") do
    line = line:gsub("^#+%s*", ""):gsub("^=+%s*", ""):gsub("^%s+", ""):gsub("%s+$", "")
    if line ~= "" and not line:match("^%-%-%-") and not line:match("^date:")
       and not line:match("^#import") and not line:match("^#set") then
      return line
    end
  end
  return ""
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
  return '"' .. s:gsub('\\', '\\\\'):gsub('"', '\\"'):gsub('\n', '\\n'):gsub('\r', '') .. '"'
end

local function hesc(s)
  return s:gsub('&','&amp;'):gsub('<','&lt;'):gsub('>','&gt;'):gsub('"','&quot;')
end

function M.generate(Wiki)
  math.randomseed(os.time())
  local notes = scan_notes(Wiki.root, Wiki.extensions)

  local nodes, node_index, edges = {}, {}, {}

  for _, path in ipairs(notes) do
    local name = vim.fn.fnamemodify(path, ":t:r")
    local ext  = vim.fn.fnamemodify(path, ":e")
    if not node_index[name] then
      node_index[name] = #nodes + 1
      local content = read_file(path)
      table.insert(nodes, {
        id      = name,
        ext     = ext,
        blurb   = get_blurb(content),
        content = content,
        links   = parse_links(content),
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
      '<div class="card" onclick="openReader(%s)"><div class="card-title">%s</div><div class="card-blurb">%s</div></div>',
      jstr(n.id), hesc(n.id), hesc(b)
    ))
  end

  local rows = {}
  for _, n in ipairs(nodes) do
    local tags = {}
    for _, l in ipairs(n.links) do
      if node_index[l] then
        table.insert(tags, string.format(
          '<span class="tag" onclick="openReader(%s)">%s</span>', jstr(l), hesc(l)
        ))
      end
    end
    local links_html = #tags > 0 and table.concat(tags) or '<span class="dim">—</span>'
    table.insert(rows, string.format(
      '<tr id="row-%s"><td class="note-name" onclick="openReader(%s)">%s</td><td>%s</td></tr>',
      hesc(n.id), jstr(n.id), hesc(n.id), links_html
    ))
  end

  local nodes_json, edges_json = {}, {}
  for _, n in ipairs(nodes) do
    local b = n.blurb ~= "" and n.blurb or "No description yet."
    if #b > 130 then b = b:sub(1, 130) .. "…" end
    table.insert(nodes_json, string.format(
      '{"id":%s,"blurb":%s,"ext":%s,"content":%s}',
      jstr(n.id), jstr(b), jstr(n.ext), jstr(n.content)
    ))
  end
  for _, e in ipairs(edges) do
    table.insert(edges_json, string.format(
      '{"source":%s,"target":%s}', jstr(e.source), jstr(e.target)
    ))
  end

  -- ── Template ───────────────────────────────────────────────────────────────

  local html = [[<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width,initial-scale=1">
<title>Brain</title>
<style>
*{box-sizing:border-box;margin:0;padding:0}
body{font-family:'Linux Libertine','Georgia',serif;background:#f8f9fa;color:#202122;height:100vh;display:flex;flex-direction:column}

header{background:#fff;border-bottom:1px solid #a2a9b1;padding:12px 28px;display:flex;align-items:baseline;gap:14px;flex-shrink:0}
header h1{font-size:1.5rem;font-weight:normal;letter-spacing:.02em}
header span{color:#54595d;font-size:.9rem}

.main{flex:1;overflow:hidden;display:flex}
.left{flex:1;overflow-y:auto;min-width:0}
.section{max-width:1120px;margin:0 auto;padding:24px}
h2{font-size:.8rem;font-weight:bold;border-bottom:1px solid #a2a9b1;padding-bottom:4px;margin-bottom:14px;text-transform:uppercase;letter-spacing:.07em;color:#54595d}

.cards{display:grid;grid-template-columns:repeat(auto-fill,minmax(175px,1fr));gap:10px;margin-bottom:32px}
.card{background:#fff;border:1px solid #a2a9b1;border-radius:2px;padding:12px;cursor:pointer;transition:box-shadow .15s}
.card:hover{box-shadow:0 2px 8px rgba(0,0,0,.12)}
.card-title{font-weight:bold;font-size:.9rem;margin-bottom:5px;color:#3366cc}
.card-blurb{font-size:.8rem;color:#54595d;line-height:1.4}

/* ── Graph ── */
#graph-wrap{background:#1a1b1e;border-radius:4px;margin-bottom:32px;position:relative;height:520px;overflow:hidden;cursor:grab}
#graph-wrap.panning{cursor:grabbing}
#graph-wrap svg{width:100%;height:100%;display:block}

.link{stroke:#3a3d45;stroke-width:1px;transition:stroke .2s}
.link.highlighted{stroke:#7b9fd4;stroke-width:2px}

.node circle{cursor:pointer;transition:r .2s}
.node text{
  font-size:11px;
  fill:#d0d3db;
  pointer-events:none;
  font-family:sans-serif;
  paint-order:stroke fill;
  stroke:#1a1b1e;
  stroke-width:3px;
  stroke-linejoin:round;
}

/* snap tooltip */
#snap{position:absolute;top:10px;left:50%;transform:translateX(-50%);background:rgba(30,32,36,.92);border:1px solid #3a3d45;border-radius:4px;padding:8px 13px;max-width:260px;font-size:.82rem;display:none;pointer-events:none;text-align:center}
#snap .t{font-weight:bold;color:#7b9fd4;margin-bottom:3px;font-family:sans-serif}
#snap .b{color:#9da3b0;line-height:1.4;font-family:sans-serif}

/* ── Controls panel ── */
#controls{position:absolute;bottom:12px;right:12px;background:rgba(26,27,30,.92);border:1px solid #3a3d45;border-radius:6px;padding:12px 14px;width:210px;font-family:sans-serif}
#controls-toggle{position:absolute;bottom:12px;right:12px;background:rgba(26,27,30,.85);border:1px solid #3a3d45;border-radius:4px;color:#9da3b0;font-size:.78rem;padding:5px 10px;cursor:pointer;display:none;font-family:sans-serif}
#controls-toggle:hover{background:rgba(50,52,60,.95)}
.ctrl-title{font-size:.72rem;font-weight:bold;text-transform:uppercase;letter-spacing:.07em;color:#6b7280;margin-bottom:10px;display:flex;justify-content:space-between;align-items:center}
.ctrl-title button{background:none;border:none;color:#6b7280;cursor:pointer;font-size:.85rem;line-height:1;padding:0 2px}
.ctrl-title button:hover{color:#d0d3db}
.ctrl-row{margin-bottom:9px}
.ctrl-label{display:flex;justify-content:space-between;font-size:.75rem;color:#9da3b0;margin-bottom:3px}
.ctrl-val{color:#7b9fd4;font-weight:bold}
input[type=range]{width:100%;height:3px;accent-color:#7b9fd4;cursor:pointer}

/* ── Table ── */
table{width:100%;border-collapse:collapse;background:#fff;font-size:.86rem}
th{text-align:left;padding:7px 12px;background:#eaecf0;border:1px solid #a2a9b1;font-weight:bold}
td{padding:6px 12px;border-bottom:1px solid #eaecf0;vertical-align:top}
tr:hover td{background:#eaf3fb}
tr.hl td{background:#fef9c3}
.note-name{color:#3366cc;cursor:pointer;font-weight:500;white-space:nowrap}
.tag{display:inline-block;background:#eaecf0;border-radius:2px;padding:1px 6px;margin:2px 2px 2px 0;font-size:.78rem;cursor:pointer;color:#3366cc}
.tag:hover{background:#c8ccd1}
.dim{color:#a2a9b1}

/* ── Reader panel ── */
#reader{width:0;flex-shrink:0;background:#fff;border-left:1px solid #a2a9b1;overflow:hidden;transition:width .25s ease;display:flex;flex-direction:column}
#reader.open{width:420px}
#reader-header{padding:14px 16px;border-bottom:1px solid #eaecf0;display:flex;align-items:center;justify-content:space-between;flex-shrink:0}
#reader-title{font-size:1.1rem;font-weight:bold;color:#202122}
#reader-close{background:none;border:none;font-size:1.3rem;cursor:pointer;color:#54595d;line-height:1;padding:2px 6px}
#reader-close:hover{color:#202122}
#reader-body{flex:1;overflow-y:auto;padding:16px}
#reader-body h1{font-size:1.2rem;margin:0 0 10px}
#reader-body h2{font-size:1rem;margin:16px 0 8px;border-bottom:1px solid #eaecf0;padding-bottom:4px;text-transform:none;letter-spacing:0;color:#202122}
#reader-body h3{font-size:.95rem;margin:14px 0 6px}
#reader-body p{margin:0 0 10px;line-height:1.6;font-size:.9rem}
#reader-body ul,#reader-body ol{margin:0 0 10px 20px}
#reader-body li{line-height:1.6;font-size:.9rem;margin-bottom:3px}
#reader-body .wikilink{color:#3366cc;cursor:pointer}
#reader-body .wikilink:hover{text-decoration:underline}
#reader-body .math-inline{font-style:italic;color:#333;background:#f8f8f8;padding:1px 4px;border-radius:2px;font-family:serif}
#reader-body .math-block{display:block;background:#f8f8f8;border-left:3px solid #a2a9b1;padding:8px 12px;margin:10px 0;font-style:italic;font-family:serif;overflow-x:auto;white-space:pre}
#reader-body blockquote{border-left:3px solid #a2a9b1;margin:10px 0;padding:4px 12px;color:#54595d;font-style:italic}
#reader-body hr{border:none;border-top:1px solid #eaecf0;margin:14px 0}
#reader-links{padding:12px 16px;border-top:1px solid #eaecf0;flex-shrink:0;font-size:.82rem}
#reader-links h3{font-size:.75rem;font-weight:bold;text-transform:uppercase;letter-spacing:.07em;color:#54595d;margin-bottom:6px}
#reader-links .link-row{margin-bottom:10px}
#reader-links .rtag{display:inline-block;background:#eaecf0;border-radius:2px;padding:2px 8px;margin:2px;font-size:.8rem;cursor:pointer;color:#3366cc}
#reader-links .rtag:hover{background:#c8ccd1}
.rnone{color:#a2a9b1;font-style:italic}
</style>
</head>
<body>
<header>
  <h1>&#x1F9E0; Brain</h1>
  <span>]] .. #nodes .. [[ notes &middot; ]] .. #edges .. [[ connections</span>
</header>
<div class="main">
<div class="left"><div class="section">

<h2>Featured</h2>
<div class="cards">]] .. table.concat(cards, "\n") .. [[</div>

<h2>Graph</h2>
<div id="graph-wrap">
  <svg id="svg"><g id="g"><g id="links-g"></g><g id="nodes-g"></g></g></svg>
  <div id="snap"><div class="t" id="snap-t"></div><div class="b" id="snap-b"></div></div>
  <div id="controls">
    <div class="ctrl-title">
      <span>Graph Settings</span>
      <button onclick="document.getElementById('controls').style.display='none';document.getElementById('controls-toggle').style.display='block'">&#x2715;</button>
    </div>
    <div class="ctrl-row">
      <div class="ctrl-label"><span>Repulsion</span><span class="ctrl-val" id="rv">280</span></div>
      <input type="range" id="s-repulse" min="50" max="700" value="280">
    </div>
    <div class="ctrl-row">
      <div class="ctrl-label"><span>Link Distance</span><span class="ctrl-val" id="ldv">120</span></div>
      <input type="range" id="s-dist" min="20" max="300" value="120">
    </div>
    <div class="ctrl-row">
      <div class="ctrl-label"><span>Center Force</span><span class="ctrl-val" id="cfv">15</span></div>
      <input type="range" id="s-center" min="1" max="60" value="15">
    </div>
    <div class="ctrl-row">
      <div class="ctrl-label"><span>Node Size</span><span class="ctrl-val" id="nsv">10</span></div>
      <input type="range" id="s-size" min="3" max="24" value="10">
    </div>
    <div class="ctrl-row">
      <div class="ctrl-label"><span>Labels</span><span class="ctrl-val" id="lv">Auto</span></div>
      <input type="range" id="s-labels" min="0" max="2" step="1" value="1">
    </div>
  </div>
  <button id="controls-toggle" onclick="document.getElementById('controls').style.display='block';this.style.display='none'">&#x2699; Settings</button>
</div>

<h2>All Notes</h2>
<table><thead><tr><th>Note</th><th>Links to</th></tr></thead>
<tbody>]] .. table.concat(rows, "\n") .. [[</tbody></table>

</div></div>

<div id="reader">
  <div id="reader-header">
    <span id="reader-title"></span>
    <button id="reader-close" onclick="closeReader()">&#x2715;</button>
  </div>
  <div id="reader-body"></div>
  <div id="reader-links">
    <div class="link-row"><h3>Wikilinks</h3><div id="reader-out"></div></div>
    <div class="link-row"><h3>Backlinks</h3><div id="reader-in"></div></div>
  </div>
</div>
</div>

<script>
const rawNodes = []] .. table.concat(nodes_json, ",") .. [[];
const rawEdges = []] .. table.concat(edges_json, ",") .. [[];

// ── SVG / zoom setup ───────────────────────────────────────────────────────
const wrap   = document.getElementById('graph-wrap');
const svg    = document.getElementById('svg');
const gEl    = document.getElementById('g');
const linksG = document.getElementById('links-g');
const nodesG = document.getElementById('nodes-g');
const NS = 'http://www.w3.org/2000/svg';
const W = svg.clientWidth, H = svg.clientHeight;

let tx = 0, ty = 0, sc = 1;
function applyTransform() {
  gEl.setAttribute('transform', `translate(${tx},${ty}) scale(${sc})`);
  updateLabelVisibility();
}

svg.addEventListener('wheel', e => {
  e.preventDefault();
  const f = e.deltaY > 0 ? 0.88 : 1.14;
  const r = svg.getBoundingClientRect();
  tx = (e.clientX - r.left) - ((e.clientX - r.left) - tx) * f;
  ty = (e.clientY - r.top)  - ((e.clientY - r.top)  - ty) * f;
  sc = Math.min(8, Math.max(0.1, sc * f));
  applyTransform();
}, { passive: false });

let panning = false, panStart = {};
svg.addEventListener('mousedown', e => {
  if (e.target === svg || e.target === gEl ||
      e.target.tagName === 'line' || e.target.tagName === 'text') {
    panning = true; wrap.classList.add('panning');
    panStart = { x: e.clientX - tx, y: e.clientY - ty };
  }
});
window.addEventListener('mousemove', e => {
  if (!panning) return;
  tx = e.clientX - panStart.x; ty = e.clientY - panStart.y; applyTransform();
});
window.addEventListener('mouseup', () => { panning = false; wrap.classList.remove('panning'); });

// ── Physics params (live-editable) ────────────────────────────────────────
let REPULSE    = -280;
let LINK_DIST  = 120;
let CENTER_F   = 0.015;
let BASE_R     = 10;
let LABEL_MODE = 1; // 0=off 1=auto 2=always

function wireSlider(id, valId, onInput) {
  const el = document.getElementById(id);
  el.addEventListener('input', () => {
    onInput(parseFloat(el.value));
    document.getElementById(valId).textContent =
      id === 's-labels' ? ['Off','Auto','Always'][parseInt(el.value)] : el.value;
    reheat();
  });
}
wireSlider('s-repulse', 'rv',     v => { REPULSE   = -v; });
wireSlider('s-dist',    'ldv',    v => { LINK_DIST  = v; });
wireSlider('s-center',  'cfv',    v => { CENTER_F   = v / 1000; });
wireSlider('s-size',    'nsv',    v => { BASE_R = v; updateNodeSizes(); });
wireSlider('s-labels',  'lv',     v => { LABEL_MODE = parseInt(v); updateLabelVisibility(); });

function updateNodeSizes() {
  nodes.forEach(n => {
    const r = BASE_R + Math.min((lc[n.id]||0) * 1.5, BASE_R);
    n._r = r;
    const el = document.getElementById('n-' + n.id);
    if (!el) return;
    el.querySelector('circle').setAttribute('r', r);
    el.querySelector('text').setAttribute('x', r + 3);
  });
}

function updateLabelVisibility() {
  nodeEls.forEach((el, i) => {
    const text = el.querySelector('text');
    if (!text) return;
    if (LABEL_MODE === 0) { text.style.opacity = 0; return; }
    if (LABEL_MODE === 2) { text.style.opacity = 1; return; }
    // auto: fade in with zoom
    const t = Math.max(0, Math.min(1, (sc - 0.5) / 0.5));
    text.style.opacity = t;
  });
}

// ── Node / link data ───────────────────────────────────────────────────────
const nodes = rawNodes.map(n => ({
  ...n,
  x: W/2 + (Math.random()-.5)*260,
  y: H/2 + (Math.random()-.5)*260,
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

const backlinks = {};
links.forEach(l => {
  if (!backlinks[l.target.id]) backlinks[l.target.id] = [];
  backlinks[l.target.id].push(l.source.id);
});

// node colour by connection count
function nodeColor(id) {
  const n = lc[id] || 0;
  if (n === 0) return '#4a4d58';
  if (n <= 2)  return '#5a7fa8';
  if (n <= 5)  return '#7b9fd4';
  return '#a8c4e8';
}

// ── SVG elements ───────────────────────────────────────────────────────────
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

  const r = BASE_R + Math.min((lc[n.id]||0) * 1.5, BASE_R);
  n._r = r;

  const circle = document.createElementNS(NS, 'circle');
  circle.setAttribute('r', r);
  circle.setAttribute('fill', nodeColor(n.id));
  circle.setAttribute('stroke', '#2a2d35');
  circle.setAttribute('stroke-width', '1.5');

  const text = document.createElementNS(NS, 'text');
  text.setAttribute('dy', '0.35em');
  text.setAttribute('x', r + 3);
  text.textContent = n.id;
  text.style.opacity = 0;

  grp.appendChild(circle);
  grp.appendChild(text);
  nodesG.appendChild(grp);

  // hover: snap tooltip + highlight edges
  grp.addEventListener('mouseenter', () => {
    document.getElementById('snap-t').textContent = n.id;
    document.getElementById('snap-b').textContent = n.blurb || 'No description.';
    document.getElementById('snap').style.display = 'block';
    // highlight connected edges
    lineEls.forEach((el, i) => {
      const l = links[i];
      const connected = l.source.id === n.id || l.target.id === n.id;
      el.classList.toggle('highlighted', connected);
    });
    // show label regardless of zoom
    text.style.opacity = 1;
  });
  grp.addEventListener('mouseleave', () => {
    document.getElementById('snap').style.display = 'none';
    lineEls.forEach(el => el.classList.remove('highlighted'));
    updateLabelVisibility();
  });

  grp.addEventListener('click', e => { e.stopPropagation(); openReader(n.id); });

  // drag
  grp.addEventListener('mousedown', e => {
    e.stopPropagation();
    const rect = svg.getBoundingClientRect();
    n.fx = n.x; n.fy = n.y; reheat();
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
const ALPHA_DECAY = 0.02, ALPHA_MIN = 0.001, VEL_DECAY = 0.42;

function simTick() {
  if (alpha < ALPHA_MIN) return;
  alpha *= (1 - ALPHA_DECAY);

  const collideR = BASE_R * 2.8;

  // center gravity
  nodes.forEach(n => {
    if (n.fx == null) n.vx += (W/2 - n.x) * CENTER_F * alpha;
    if (n.fy == null) n.vy += (H/2 - n.y) * CENTER_F * alpha;
  });

  // repulsion
  for (let i = 0; i < nodes.length; i++) {
    for (let j = i+1; j < nodes.length; j++) {
      const a = nodes[i], b = nodes[j];
      const dx = b.x-a.x, dy = b.y-a.y, d = Math.sqrt(dx*dx+dy*dy)||1;
      const f = REPULSE/(d*d)*alpha;
      if (a.fx==null){a.vx-=f*dx/d; a.vy-=f*dy/d;}
      if (b.fx==null){b.vx+=f*dx/d; b.vy+=f*dy/d;}
    }
  }

  // spring
  links.forEach(l => {
    const dx = l.target.x-l.source.x, dy = l.target.y-l.source.y;
    const d = Math.sqrt(dx*dx+dy*dy)||1;
    const f = (d-LINK_DIST)/d*0.28*alpha;
    if (l.source.fx==null){l.source.vx+=f*dx; l.source.vy+=f*dy;}
    if (l.target.fx==null){l.target.vx-=f*dx; l.target.vy-=f*dy;}
  });

  // collision
  for (let i = 0; i < nodes.length; i++) {
    for (let j = i+1; j < nodes.length; j++) {
      const a = nodes[i], b = nodes[j];
      const dx = b.x-a.x, dy = b.y-a.y, d = Math.sqrt(dx*dx+dy*dy)||1;
      if (d < collideR) {
        const ov = (collideR-d)/d*0.5;
        if (a.fx==null){a.vx-=dx*ov; a.vy-=dy*ov;}
        if (b.fx==null){b.vx+=dx*ov; b.vy+=dy*ov;}
      }
    }
  }

  // integrate
  nodes.forEach(n => {
    if (n.fx!=null){n.x=n.fx;n.vx=0;}else{n.vx*=(1-VEL_DECAY);n.x+=n.vx;}
    if (n.fy!=null){n.y=n.fy;n.vy=0;}else{n.vy*=(1-VEL_DECAY);n.y+=n.vy;}
  });

  lineEls.forEach((el,i) => {
    el.setAttribute('x1',links[i].source.x); el.setAttribute('y1',links[i].source.y);
    el.setAttribute('x2',links[i].target.x); el.setAttribute('y2',links[i].target.y);
  });
  nodeEls.forEach((el,i) => el.setAttribute('transform',`translate(${nodes[i].x},${nodes[i].y})`));
  requestAnimationFrame(simTick);
}
function reheat() { alpha = 0.3; requestAnimationFrame(simTick); }
requestAnimationFrame(simTick);

// ── Note renderer ──────────────────────────────────────────────────────────
function renderContent(raw, ext) {
  const blocks = [];
  let text = raw.replace(/\$\$[\s\S]*?\$\$/g, m => {
    blocks.push(m.slice(2,-2).trim()); return '\x00BLOCK'+(blocks.length-1)+'\x00';
  });
  if (ext==='typ') {
    text = text.replace(/^\$\n([\s\S]*?)\n\$$/gm, (_,inner) => {
      blocks.push(inner.trim()); return '\x00BLOCK'+(blocks.length-1)+'\x00';
    });
    text = text.replace(/^#(import|set|show|let)[^\n]*/gm,'');
  }
  const lines = text.split('\n'), out = [];
  let inList = false;
  for (const l of lines) {
    if (/^=== /.test(l))     {if(inList){out.push('</ul>');inList=false;}out.push('<h3>'+inline(l.slice(4),ext)+'</h3>');continue;}
    if (/^== /.test(l))      {if(inList){out.push('</ul>');inList=false;}out.push('<h2>'+inline(l.slice(3),ext)+'</h2>');continue;}
    if (/^= /.test(l))       {if(inList){out.push('</ul>');inList=false;}out.push('<h1>'+inline(l.slice(2),ext)+'</h1>');continue;}
    if (/^### /.test(l))     {if(inList){out.push('</ul>');inList=false;}out.push('<h3>'+inline(l.slice(4),ext)+'</h3>');continue;}
    if (/^## /.test(l))      {if(inList){out.push('</ul>');inList=false;}out.push('<h2>'+inline(l.slice(3),ext)+'</h2>');continue;}
    if (/^# /.test(l))       {if(inList){out.push('</ul>');inList=false;}out.push('<h1>'+inline(l.slice(2),ext)+'</h1>');continue;}
    if (/^---+$/.test(l.trim())){if(inList){out.push('</ul>');inList=false;}out.push('<hr>');continue;}
    if (/^\x00BLOCK\d+\x00$/.test(l.trim())){
      if(inList){out.push('</ul>');inList=false;}
      out.push('<div class="math-block">'+esc(blocks[parseInt(l.match(/\d+/)[0])])+'</div>');continue;
    }
    if (/^[-*] /.test(l)){if(!inList){out.push('<ul>');inList=true;}out.push('<li>'+inline(l.slice(2),ext)+'</li>');continue;}
    if (l.trim()===''){if(inList){out.push('</ul>');inList=false;}continue;}
    if (inList){out.push('</ul>');inList=false;}
    out.push('<p>'+inline(l,ext)+'</p>');
  }
  if (inList) out.push('</ul>');
  return out.join('\n');
}

function inline(s, ext) {
  s = s.replace(/\[\[([^\]|]+)(?:\|([^\x5D]+))?\]\]/g, (_,target,alias) => {
    const id = target.trim().replace(/\.[a-z]+$/,'');
    return `<span class="wikilink" onclick="openReader(${JSON.stringify(id)})">${esc((alias||id).trim())}</span>`;
  });
  s = s.replace(/\$([^$\n]+)\$/g, (_,m) => `<span class="math-inline">${esc(m)}</span>`);
  s = s.replace(/\*\*\*(.+?)\*\*\*/g, (_,m) => `<strong><em>${esc(m)}</em></strong>`);
  s = s.replace(/\*\*(.+?)\*\*/g,     (_,m) => `<strong>${esc(m)}</strong>`);
  s = s.replace(/\*(.+?)\*/g,         (_,m) => `<em>${esc(m)}</em>`);
  s = s.replace(/_([^_\n]+)_/g,       (_,m) => `<em>${esc(m)}</em>`);
  if (/^> /.test(s)) s = `<blockquote>${s.slice(2)}</blockquote>`;
  return s;
}
function esc(s){ return s.replace(/&/g,'&amp;').replace(/</g,'&lt;').replace(/>/g,'&gt;'); }

// ── Reader panel ───────────────────────────────────────────────────────────
function openReader(id) {
  const n = nodeById[id];
  if (!n) return;
  document.getElementById('reader-title').textContent = n.id;
  document.getElementById('reader-body').innerHTML = renderContent(n.content, n.ext);
  document.getElementById('reader').classList.add('open');
  const rawOut = rawEdges.filter(e => e.source===id).map(e => e.target);
  const rawIn  = backlinks[id] || [];
  document.getElementById('reader-out').innerHTML = rawOut.length
    ? rawOut.map(t=>`<span class="rtag" onclick="openReader(${JSON.stringify(t)})">${esc(t)}</span>`).join('')
    : '<span class="rnone">none</span>';
  document.getElementById('reader-in').innerHTML = rawIn.length
    ? rawIn.map(s=>`<span class="rtag" onclick="openReader(${JSON.stringify(s)})">${esc(s)}</span>`).join('')
    : '<span class="rnone">none</span>';
  document.querySelectorAll('.node.focused').forEach(el=>el.classList.remove('focused'));
  const el = document.getElementById('n-'+id);
  if (el) el.classList.add('focused');
  const row = document.getElementById('row-'+id);
  if (row){
    document.querySelectorAll('tr.hl').forEach(r=>r.classList.remove('hl'));
    row.classList.add('hl');
    row.scrollIntoView({behavior:'smooth',block:'nearest'});
  }
}
function closeReader(){
  document.getElementById('reader').classList.remove('open');
  document.querySelectorAll('.node.focused').forEach(el=>el.classList.remove('focused'));
}
function focusNode(id){ openReader(id); }
</script>
</body>
</html>]]

  local out = Wiki.root .. "/brain.html"
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
