import fs from 'node:fs/promises';
import http from 'node:http';
import path from 'node:path';

const apiPort = Number(process.env.NATIVE_MANAGER_API_PORT ?? '3311');
const uiPort = Number(process.env.NATIVE_MANAGER_UI_PORT ?? '3101');
const webRoot = process.env.NATIVE_MANAGER_WEB_ROOT;

if (!webRoot) {
  console.error('缺少 NATIVE_MANAGER_WEB_ROOT');
  process.exit(1);
}

function contentTypeFor(filePath) {
  const ext = path.extname(filePath).toLowerCase();
  switch (ext) {
    case '.css':
      return 'text/css; charset=utf-8';
    case '.html':
      return 'text/html; charset=utf-8';
    case '.js':
    case '.mjs':
      return 'application/javascript; charset=utf-8';
    case '.json':
      return 'application/json; charset=utf-8';
    case '.svg':
      return 'image/svg+xml';
    case '.png':
      return 'image/png';
    case '.jpg':
    case '.jpeg':
      return 'image/jpeg';
    case '.ico':
      return 'image/x-icon';
    case '.woff':
      return 'font/woff';
    case '.woff2':
      return 'font/woff2';
    default:
      return 'application/octet-stream';
  }
}

async function pathExists(targetPath) {
  try {
    await fs.stat(targetPath);
    return true;
  } catch {
    return false;
  }
}

function proxyApi(req, res) {
  const upstream = http.request(
    {
      hostname: '127.0.0.1',
      port: apiPort,
      method: req.method,
      path: req.url,
      headers: { ...req.headers, host: `127.0.0.1:${apiPort}` }
    },
    (upstreamRes) => {
      res.writeHead(upstreamRes.statusCode ?? 502, upstreamRes.headers);
      upstreamRes.pipe(res);
    }
  );

  upstream.on('error', (error) => {
    if (!res.headersSent) {
      res.writeHead(502, { 'content-type': 'application/json; charset=utf-8' });
    }
    res.end(JSON.stringify({ error: error instanceof Error ? error.message : 'proxy error' }));
  });

  req.pipe(upstream);
}

async function serveStatic(req, res) {
  const urlPath = decodeURIComponent((req.url || '/').split('?')[0]);
  const relative = urlPath === '/' ? 'index.html' : urlPath.replace(/^\/+/, '');
  const resolved = path.resolve(webRoot, relative);
  const root = `${path.resolve(webRoot)}${path.sep}`;

  let target = resolved;
  if (!resolved.startsWith(root) && resolved !== path.resolve(webRoot, 'index.html')) {
    target = path.resolve(webRoot, 'index.html');
  }

  if (!(await pathExists(target))) {
    target = path.resolve(webRoot, 'index.html');
  }

  const body = await fs.readFile(target);
  res.writeHead(200, { 'content-type': contentTypeFor(target) });
  res.end(body);
}

const server = http.createServer((req, res) => {
  if ((req.url || '').startsWith('/api/')) {
    proxyApi(req, res);
    return;
  }

  if ((req.url || '') === '/__native_ui_health') {
    res.writeHead(200, { 'content-type': 'application/json; charset=utf-8' });
    res.end(JSON.stringify({ ok: true }));
    return;
  }

  serveStatic(req, res).catch((error) => {
    if (!res.headersSent) {
      res.writeHead(500, { 'content-type': 'text/plain; charset=utf-8' });
    }
    res.end(error instanceof Error ? error.message : 'static error');
  });
});

server.listen(uiPort, '127.0.0.1', () => {
  console.log(`[native-ui] listening on http://127.0.0.1:${uiPort}`);
});

