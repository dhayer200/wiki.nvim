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

#graph-wrap{background:#fff;border:1px solid #a2a9b1;border-radius:2px;margin-bottom:32px;position:relative;height:480px;overflow:hidden;cursor:grab}
#graph-wrap.panning{cursor:grabbing}
#graph-wrap svg{width:100%;height:100%;display:block}
.link{stroke:#c8ccd1;stroke-width:1px}
.node circle{stroke:#a2a9b1;stroke-width:1.5px;fill:#eaf3fb;cursor:pointer;transition:fill .15s}
.node:hover circle,.node.focused circle{fill:#3366cc}
.node text{font-size:10px;fill:#202122;pointer-events:none;font-family:sans-serif}

#snap{position:absolute;top:10px;right:10px;background:#fff;border:1px solid #a2a9b1;border-radius:2px;padding:10px 13px;max-width:200px;font-size:.82rem;display:none;box-shadow:0 2px 6px rgba(0,0,0,.1);pointer-events:none}
#snap .t{font-weight:bold;color:#3366cc;margin-bottom:4px}
#snap .b{color:#54595d;line-height:1.4}

table{width:100%;border-collapse:collapse;background:#fff;font-size:.86rem}
th{text-align:left;padding:7px 12px;background:#eaecf0;border:1px solid #a2a9b1;font-weight:bold}
td{padding:6px 12px;border-bottom:1px solid #eaecf0;vertical-align:top}
tr:hover td{background:#eaf3fb}
tr.hl td{background:#fef9c3}
.note-name{color:#3366cc;cursor:pointer;font-weight:500;white-space:nowrap}
.tag{display:inline-block;background:#eaecf0;border-radius:2px;padding:1px 6px;margin:2px 2px 2px 0;font-size:.78rem;cursor:pointer;color:#3366cc}
.tag:hover{background:#c8ccd1}
.dim{color:#a2a9b1}

/* ── Reader panel ─────────────────────────────────────────────────────────── */
#reader{width:0;flex-shrink:0;background:#fff;border-left:1px solid #a2a9b1;overflow:hidden;transition:width .25s ease;display:flex;flex-direction:column}
#reader.open{width:420px}
#reader-header{padding:14px 16px;border-bottom:1px solid #eaecf0;display:flex;align-items:center;justify-content:space-between;flex-shrink:0}
#reader-title{font-size:1.1rem;font-weight:bold;color:#202122}
#reader-close{background:none;border:none;font-size:1.3rem;cursor:pointer;color:#54595d;line-height:1;padding:2px 6px}
#reader-close:hover{color:#202122}
#reader-body{flex:1;overflow-y:auto;padding:16px}

/* rendered note content */
#reader-body h1{font-size:1.2rem;margin:0 0 10px}
#reader-body h2{font-size:1rem;margin:16px 0 8px;border-bottom:1px solid #eaecf0;padding-bottom:4px;text-transform:none;letter-spacing:0;color:#202122}
#reader-body h3{font-size:.95rem;margin:14px 0 6px}
#reader-body p{margin:0 0 10px;line-height:1.6;font-size:.9rem}
#reader-body ul,#reader-body ol{margin:0 0 10px 20px}
#reader-body li{line-height:1.6;font-size:.9rem;margin-bottom:3px}
#reader-body .wikilink{color:#3366cc;cursor:pointer;text-decoration:none}
#reader-body .wikilink:hover{text-decoration:underline}
#reader-body .math-inline{font-style:italic;color:#333;background:#f8f8f8;padding:1px 4px;border-radius:2px;font-family:serif}
#reader-body .math-block{display:block;background:#f8f8f8;border-left:3px solid #a2a9b1;padding:8px 12px;margin:10px 0;font-style:italic;font-family:serif;overflow-x:auto;white-space:pre}
#reader-body blockquote{border-left:3px solid #a2a9b1;margin:10px 0;padding:4px 12px;color:#54595d;font-style:italic}
#reader-body hr{border:none;border-top:1px solid #eaecf0;margin:14px 0}
#reader-body strong{font-weight:bold}
#reader-body em{font-style:italic}

#reader-links{padding:12px 16px;border-top:1px solid #eaecf0;flex-shrink:0;font-size:.82rem}
#reader-links h3{font-size:.75rem;font-weight:bold;text-transform:uppercase;letter-spacing:.07em;color:#54595d;margin-bottom:6px}
#reader-links .link-row{margin-bottom:10px}
#reader-links .rtag{display:inline-block;background:#eaecf0;border-radius:2px;padding:2px 8px;margin:2px;font-size:.8rem;cursor:pointer;color:#3366cc}
#reader-links .rtag:hover{background:#c8ccd1}
.none{color:#a2a9b1;font-style:italic}
</style>
</head>
<body>
<header>
  <h1>&#x1F9E0; Brain</h1>
  <span>]] .. #nodes .. [[ notes &middot; ]] .. #edges .. [[ connections</span>
</header>
<div class="main">
<div class="left">
<div class="section">
  <h2>Featured</h2>
  <div class="cards">]] .. table.concat(cards, "\n") .. [[</div>
  <h2>Graph</h2>
  <div id="graph-wrap">
    <svg id="svg"><g id="g"><g id="links-g"></g><g id="nodes-g"></g></g></svg>
    <div id="snap"><div class="t" id="snap-t"></div><div class="b" id="snap-b"></div></div>
  </div>
  <h2>All Notes</h2>
  <table><thead><tr><th>Note</th><th>Links to</th></tr></thead>
  <tbody>]] .. table.concat(rows, "\n") .. [[</tbody></table>
</div>
</div>

<!-- reader panel -->
<div id="reader">
  <div id="reader-header">
    <span id="reader-title"></span>
    <button id="reader-close" onclick="closeReader()">&#x2715;</button>
  </div>
  <div id="reader-body"></div>
  <div id="reader-links">
    <div class="link-row">
      <h3>Wikilinks</h3>
      <div id="reader-out"></div>
    </div>
    <div class="link-row">
      <h3>Backlinks</h3>
      <div id="reader-in"></div>
    </div>
  </div>
</div>
</div>

<script>
const rawNodes = []] .. table.concat(nodes_json, ",") .. [[];
const rawEdges = []] .. table.concat(edges_json, ",") .. [[];

// ── Graph setup ────────────────────────────────────────────────────────────
const wrap   = document.getElementById('graph-wrap');
const svg    = document.getElementById('svg');
const g      = document.getElementById('g');
const linksG = document.getElementById('links-g');
const nodesG = document.getElementById('nodes-g');
const NS = 'http://www.w3.org/2000/svg';
const W = svg.clientWidth, H = svg.clientHeight;

let tx = 0, ty = 0, sc = 1;
function applyTransform() { g.setAttribute('transform', `translate(${tx},${ty}) scale(${sc})`); }

svg.addEventListener('wheel', e => {
  e.preventDefault();
  const f = e.deltaY > 0 ? 0.88 : 1.14;
  const r = svg.getBoundingClientRect();
  const mx = e.clientX - r.left, my = e.clientY - r.top;
  tx = mx - (mx - tx) * f;
  ty = my - (my - ty) * f;
  sc = Math.min(6, Math.max(0.15, sc * f));
  applyTransform();
}, { passive: false });

let panning = false, panStart = {};
svg.addEventListener('mousedown', e => {
  if (e.target === svg || e.target === g || e.target.tagName === 'line' ||
      (e.target.tagName === 'text')) {
    panning = true; wrap.classList.add('panning');
    panStart = { x: e.clientX - tx, y: e.clientY - ty };
  }
});
window.addEventListener('mousemove', e => {
  if (!panning) return;
  tx = e.clientX - panStart.x; ty = e.clientY - panStart.y; applyTransform();
});
window.addEventListener('mouseup', () => { panning = false; wrap.classList.remove('panning'); });

// ── Node / link data ───────────────────────────────────────────────────────
const nodes = rawNodes.map(n => ({
  ...n, x: W/2 + (Math.random()-.5)*300, y: H/2 + (Math.random()-.5)*300,
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

// backlinks map
const backlinks = {};
links.forEach(l => {
  if (!backlinks[l.target.id]) backlinks[l.target.id] = [];
  backlinks[l.target.id].push(l.source.id);
});

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
  const r = 7 + Math.min((lc[n.id]||0) * 1.6, 11);
  const circle = document.createElementNS(NS, 'circle');
  circle.setAttribute('r', r);
  const text = document.createElementNS(NS, 'text');
  text.setAttribute('dy', '0.35em');
  text.setAttribute('x', r + 3);
  text.textContent = n.id;
  grp.appendChild(circle); grp.appendChild(text);
  nodesG.appendChild(grp);

  grp.addEventListener('mouseenter', () => {
    document.getElementById('snap-t').textContent = n.id;
    document.getElementById('snap-b').textContent = n.blurb || 'No description yet.';
    document.getElementById('snap').style.display = 'block';
  });
  grp.addEventListener('mouseleave', () => {
    document.getElementById('snap').style.display = 'none';
  });
  grp.addEventListener('click', e => { e.stopPropagation(); openReader(n.id); });

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
const LINK_DIST = 120, REPULSE = -280, COLLIDE_R = 28;

function simTick() {
  if (alpha < ALPHA_MIN) return;
  alpha *= (1 - ALPHA_DECAY);

  nodes.forEach(n => {
    if (n.fx == null) n.vx += (W/2 - n.x) * 0.015 * alpha;
    if (n.fy == null) n.vy += (H/2 - n.y) * 0.015 * alpha;
  });

  for (let i = 0; i < nodes.length; i++) {
    for (let j = i+1; j < nodes.length; j++) {
      const a = nodes[i], b = nodes[j];
      const dx = b.x-a.x, dy = b.y-a.y, d = Math.sqrt(dx*dx+dy*dy)||1;
      const f = REPULSE/(d*d)*alpha;
      if (a.fx==null){a.vx-=f*dx/d; a.vy-=f*dy/d;}
      if (b.fx==null){b.vx+=f*dx/d; b.vy+=f*dy/d;}
    }
  }

  links.forEach(l => {
    const dx = l.target.x-l.source.x, dy = l.target.y-l.source.y;
    const d = Math.sqrt(dx*dx+dy*dy)||1;
    const f = (d-LINK_DIST)/d*0.28*alpha;
    if (l.source.fx==null){l.source.vx+=f*dx; l.source.vy+=f*dy;}
    if (l.target.fx==null){l.target.vx-=f*dx; l.target.vy-=f*dy;}
  });

  for (let i = 0; i < nodes.length; i++) {
    for (let j = i+1; j < nodes.length; j++) {
      const a = nodes[i], b = nodes[j];
      const dx = b.x-a.x, dy = b.y-a.y, d = Math.sqrt(dx*dx+dy*dy)||1;
      if (d < COLLIDE_R) {
        const ov = (COLLIDE_R-d)/d*0.5;
        if (a.fx==null){a.vx-=dx*ov; a.vy-=dy*ov;}
        if (b.fx==null){b.vx+=dx*ov; b.vy+=dy*ov;}
      }
    }
  }

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
  // strip display math blocks first, replace with placeholder
  const blocks = [];
  let text = raw.replace(/\$\$[\s\S]*?\$\$/g, m => {
    blocks.push(m.slice(2, -2).trim());
    return '\x00BLOCK' + (blocks.length-1) + '\x00';
  });
  // typst display math: $ ... $ on its own line (has spaces around content)
  if (ext === 'typ') {
    text = text.replace(/^\$\n([\s\S]*?)\n\$$/gm, (_, inner) => {
      blocks.push(inner.trim());
      return '\x00BLOCK' + (blocks.length-1) + '\x00';
    });
    // typst #import, #set, #show — skip
    text = text.replace(/^#(import|set|show|let)[^\n]*/gm, '');
  }

  const lines = text.split('\n');
  const out = [];
  let inList = false;

  for (let i = 0; i < lines.length; i++) {
    let l = lines[i];

    // headings
    if (/^=== /.test(l))      { if(inList){out.push('</ul>');inList=false;} out.push('<h3>'+inline(l.slice(4),ext)+'</h3>'); continue; }
    if (/^== /.test(l))       { if(inList){out.push('</ul>');inList=false;} out.push('<h2>'+inline(l.slice(3),ext)+'</h2>'); continue; }
    if (/^= /.test(l))        { if(inList){out.push('</ul>');inList=false;} out.push('<h1>'+inline(l.slice(2),ext)+'</h1>'); continue; }
    if (/^### /.test(l))      { if(inList){out.push('</ul>');inList=false;} out.push('<h3>'+inline(l.slice(4),ext)+'</h3>'); continue; }
    if (/^## /.test(l))       { if(inList){out.push('</ul>');inList=false;} out.push('<h2>'+inline(l.slice(3),ext)+'</h2>'); continue; }
    if (/^# /.test(l))        { if(inList){out.push('</ul>');inList=false;} out.push('<h1>'+inline(l.slice(2),ext)+'</h1>'); continue; }
    if (/^---+$/.test(l.trim())) { if(inList){out.push('</ul>');inList=false;} out.push('<hr>'); continue; }

    // block math placeholder
    if (/^\x00BLOCK\d+\x00$/.test(l.trim())) {
      if(inList){out.push('</ul>');inList=false;}
      const idx = parseInt(l.match(/\d+/)[0]);
      out.push('<div class="math-block">'+esc(blocks[idx])+'</div>');
      continue;
    }

    // list items
    if (/^[-*] /.test(l)) {
      if (!inList) { out.push('<ul>'); inList = true; }
      out.push('<li>'+inline(l.slice(2),ext)+'</li>');
      continue;
    }

    // empty line
    if (l.trim() === '') {
      if (inList) { out.push('</ul>'); inList = false; }
      continue;
    }

    if (inList) { out.push('</ul>'); inList = false; }
    out.push('<p>'+inline(l,ext)+'</p>');
  }
  if (inList) out.push('</ul>');
  return out.join('\n');
}

function inline(s, ext) {
  // wikilinks
  s = s.replace(/\[\[([^\]|]+)(?:\|([^\]]+))?\]\]/g, (_, target, alias) => {
    const id = target.trim().replace(/\.[a-z]+$/, '');
    const label = (alias || id).trim();
    return `<span class="wikilink" onclick="openReader(${JSON.stringify(id)})">${esc(label)}</span>`;
  });
  // inline math
  s = s.replace(/\$([^$\n]+)\$/g, (_, m) => `<span class="math-inline">${esc(m)}</span>`);
  // bold + italic (md)
  s = s.replace(/\*\*\*(.+?)\*\*\*/g, (_,m)=>`<strong><em>${esc(m)}</em></strong>`);
  s = s.replace(/\*\*(.+?)\*\*/g,     (_,m)=>`<strong>${esc(m)}</strong>`);
  s = s.replace(/\*(.+?)\*/g,         (_,m)=>`<em>${esc(m)}</em>`);
  s = s.replace(/_([^_\n]+)_/g,       (_,m)=>`<em>${esc(m)}</em>`);
  // blockquote inline (> at start)
  if (/^> /.test(s)) s = `<blockquote>${s.slice(2)}</blockquote>`;
  return s;
}

function esc(s) {
  return s.replace(/&/g,'&amp;').replace(/</g,'&lt;').replace(/>/g,'&gt;');
}

// ── Reader panel ───────────────────────────────────────────────────────────
function openReader(id) {
  const n = nodeById[id];
  if (!n) return;

  document.getElementById('reader-title').textContent = n.id;
  document.getElementById('reader-body').innerHTML = renderContent(n.content, n.ext);
  document.getElementById('reader').classList.add('open');

  // outgoing links
  const outLinks = (backlinks[id] ? [] : []).concat([]); // just use raw link data
  const rawOut = rawEdges.filter(e => e.source === id).map(e => e.target);
  const rawIn  = (backlinks[id] || []);

  const outDiv = document.getElementById('reader-out');
  const inDiv  = document.getElementById('reader-in');

  outDiv.innerHTML = rawOut.length
    ? rawOut.map(t => `<span class="rtag" onclick="openReader(${JSON.stringify(t)})">${esc(t)}</span>`).join('')
    : '<span class="none">none</span>';

  inDiv.innerHTML = rawIn.length
    ? rawIn.map(s => `<span class="rtag" onclick="openReader(${JSON.stringify(s)})">${esc(s)}</span>`).join('')
    : '<span class="none">none</span>';

  // highlight in graph and table
  document.querySelectorAll('.node.focused').forEach(el => el.classList.remove('focused'));
  const el = document.getElementById('n-' + id);
  if (el) el.classList.add('focused');
  const row = document.getElementById('row-' + id);
  if (row) {
    document.querySelectorAll('tr.hl').forEach(r => r.classList.remove('hl'));
    row.classList.add('hl');
    row.scrollIntoView({ behavior: 'smooth', block: 'nearest' });
  }
}

function closeReader() {
  document.getElementById('reader').classList.remove('open');
  document.querySelectorAll('.node.focused').forEach(el => el.classList.remove('focused'));
}

function focusNode(id) { openReader(id); }
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
