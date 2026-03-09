'use strict';
const http       = require('node:http');
const fs         = require('node:fs');
const path       = require('node:path');
const os         = require('node:os');
const { execFile } = require('node:child_process');

const renderCache = new Map(); // id -> { mtime, html }

const [,, wikiRoot, portArg] = process.argv;
const PORT = parseInt(portArg) || 5757;
const EXTS = ['md', 'typ', 'txt'];

// ── wiki scanning ──────────────────────────────────────────────────────────
function scanWiki() {
  const nodes = [], nodeSet = new Set(), edges = [];
  let files;
  try { files = fs.readdirSync(wikiRoot); }
  catch (e) { process.stderr.write('scan error: ' + e.message + '\n'); return { nodes, edges }; }

  for (const f of files) {
    const dot = f.lastIndexOf('.');
    if (dot < 0) continue;
    const ext = f.slice(dot + 1);
    if (!EXTS.includes(ext)) continue;
    const name = f.slice(0, dot);
    if (nodeSet.has(name)) continue;
    nodeSet.add(name);
    let content = '';
    try { content = fs.readFileSync(path.join(wikiRoot, f), 'utf8'); } catch {}
    nodes.push({ id: name, ext, content, blurb: getBlurb(content) });
  }

  for (const node of nodes) {
    for (const link of parseLinks(node.content)) {
      if (nodeSet.has(link)) edges.push({ source: node.id, target: link });
    }
  }
  return { nodes, edges };
}

function getBlurb(content) {
  for (const line of content.split('\n')) {
    const l = line.replace(/^#+\s*/, '').replace(/^=+\s*/, '').trim();
    if (l && !l.startsWith('---') && !l.startsWith('date:') &&
        !l.startsWith('#import') && !l.startsWith('#set')) {
      return l.length > 130 ? l.slice(0, 130) + '\u2026' : l;
    }
  }
  return '';
}

function parseLinks(content) {
  const links = [], seen = new Set();
  for (const m of content.matchAll(/\[\[([^\]|]+)[|\]]/g)) {
    const link = m[1].trim().replace(/\.[a-z]+$/, '');
    if (link && !seen.has(link)) { seen.add(link); links.push(link); }
  }
  return links;
}

// ── SSE clients ────────────────────────────────────────────────────────────
const sseClients = new Set();
let debounce = null;
try {
  fs.watch(wikiRoot, { persistent: false }, (_, filename) => {
    if (filename && filename.endsWith('.typ')) {
      renderCache.delete(filename.slice(0, -4));
    }
    clearTimeout(debounce);
    debounce = setTimeout(() => {
      for (const res of sseClients) res.write('data: refresh\n\n');
    }, 400);
  });
} catch {}

// ── Serve graph.html ───────────────────────────────────────────────────────
const htmlPath = path.join(__dirname, 'graph.html');

const server = http.createServer((req, res) => {
  const url = new URL(req.url, `http://127.0.0.1:${PORT}`);

  if (req.method === 'GET' && url.pathname === '/') {
    let html;
    try { html = fs.readFileSync(htmlPath, 'utf8'); }
    catch (e) { res.writeHead(500); res.end('graph.html not found'); return; }
    res.writeHead(200, { 'Content-Type': 'text/html; charset=utf-8' });
    res.end(html);
    return;
  }

  if (req.method === 'GET' && url.pathname === '/data') {
    const data = scanWiki();
    res.writeHead(200, { 'Content-Type': 'application/json', 'Cache-Control': 'no-cache' });
    res.end(JSON.stringify(data));
    return;
  }

  if (req.method === 'GET' && url.pathname === '/events') {
    res.writeHead(200, {
      'Content-Type': 'text/event-stream',
      'Cache-Control': 'no-cache',
      'Connection': 'keep-alive',
    });
    res.write('data: connected\n\n');
    sseClients.add(res);
    req.on('close', () => sseClients.delete(res));
    return;
  }

  if (req.method === 'GET' && url.pathname === '/render') {
    const id = url.searchParams.get('id');
    if (!id) { res.writeHead(400); res.end('missing id'); return; }

    const typFile = path.join(wikiRoot, id + '.typ');
    let mtime;
    try { mtime = fs.statSync(typFile).mtimeMs; }
    catch { res.writeHead(404); res.end('not found'); return; }

    const cached = renderCache.get(id);
    if (cached && cached.mtime === mtime) {
      res.writeHead(200, { 'Content-Type': 'text/html; charset=utf-8' });
      res.end(cached.html);
      return;
    }

    let tmpDir;
    try { tmpDir = fs.mkdtempSync(path.join(os.tmpdir(), 'wiki-typst-')); }
    catch { res.writeHead(500); res.end('tmpdir error'); return; }

    const outPath = path.join(tmpDir, 'out.svg');
    const execEnv = { ...process.env, PATH: '/opt/homebrew/bin:/usr/local/bin:/usr/bin:' + (process.env.PATH || '') };
    execFile('typst', ['compile', typFile, outPath], { env: execEnv }, err => {
      if (err) {
        try { fs.rmSync(tmpDir, { recursive: true }); } catch {}
        res.writeHead(500); res.end('typst: ' + err.message);
        return;
      }
      let svgs = [];
      try {
        svgs = fs.readdirSync(tmpDir)
          .filter(f => f.endsWith('.svg'))
          .sort()
          .map(f => fs.readFileSync(path.join(tmpDir, f), 'utf8'));
      } catch {}
      try { fs.rmSync(tmpDir, { recursive: true }); } catch {}

      if (svgs.length === 0) { res.writeHead(500); res.end('no output'); return; }

      const html = svgs.map(s => `<div class="typst-page">${s}</div>`).join('');
      renderCache.set(id, { mtime, html });
      res.writeHead(200, { 'Content-Type': 'text/html; charset=utf-8' });
      res.end(html);
    });
    return;
  }

  if (req.method === 'POST' && url.pathname === '/open') {
    let body = '';
    req.on('data', d => { body += d; });
    req.on('end', () => {
      try {
        const { file } = JSON.parse(body);
        if (file) process.stdout.write('OPEN:' + file + '\n');
      } catch {}
      res.writeHead(204);
      res.end();
    });
    return;
  }

  res.writeHead(404);
  res.end();
});

server.on('error', e => {
  process.stderr.write('WikiGraph error: ' + e.message + '\n');
  process.exit(1);
});

server.listen(PORT, '127.0.0.1', () => {
  process.stderr.write('WikiGraph listening on http://127.0.0.1:' + PORT + '\n');
});
