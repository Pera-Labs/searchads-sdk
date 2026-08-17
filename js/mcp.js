#!/usr/bin/env node
// searchads-sdk MCP server — exposes the searchads.tools agent API as MCP tools.
// Zero dependencies: speaks MCP (JSON-RPC 2.0 over stdio, newline-delimited).
//
// Usage:
//   SEARCHADS_API_KEY=sa_... npx -y github:Pera-Labs/searchads-sdk searchads-mcp
// or in Claude Code:
//   claude mcp add searchads -e SEARCHADS_API_KEY=sa_... -- npx -y github:Pera-Labs/searchads-sdk searchads-mcp
//
// The api key is read from the environment only — never passed as an argument,
// never logged.

const API_KEY = process.env.SEARCHADS_API_KEY || '';
const BASE = (process.env.SEARCHADS_BASE_URL || 'https://searchads.tools').replace(/\/+$/, '');

if (!API_KEY) {
  process.stderr.write('searchads-mcp: SEARCHADS_API_KEY env var is required (sa_... key from searchads.tools)\n');
  process.exit(1);
}

const num = { type: 'number' };
const str = { type: 'string' };

const TOOLS = [
  { name: 'account_info', endpoint: 'me', description: 'Account info for this api key: label, app token presence, ASA connection status, available endpoints.', params: {} },
  { name: 'events_summary', endpoint: 'events', description: 'Event summary for the last N hours: totals + unique users per event name, 50 most recent events, core funnel counts.', params: { hours: num } },
  { name: 'list_users', endpoint: 'users', description: 'List users with pro status, country and ASA attribution.', params: { limit: num, offset: num, sortBy: str, is_pro: str, country: str, attribution_keyword: str } },
  { name: 'user_timeline', endpoint: 'user/{user_id}', description: 'Full event timeline for one user id.', params: { user_id: { ...str, required: true } } },
  { name: 'retention', endpoint: 'retention', description: 'Cohort retention table.', params: { sinceDays: num } },
  { name: 'funnel_by_keyword', endpoint: 'funnel-by-keyword', description: 'Conversion funnel split by Apple Search Ads keyword. events param is a comma-separated ordered list of event names.', params: { events: str, sinceHours: num } },
  { name: 'geo_breakdown', endpoint: 'geo', description: 'Events broken down by country.', params: { sinceHours: num } },
  { name: 'hourly_events', endpoint: 'hourly', description: 'Events per hour for the last N hours.', params: { sinceHours: num } },
  { name: 'revenue_by_keyword', endpoint: 'revenue-by-keyword', description: 'Revenue attributed per Apple Search Ads keyword.', params: { sinceDays: num } },
  { name: 'roas', endpoint: 'roas', description: 'Revenue vs ad-spend rollup (ROAS). Works without ASA connected (spend will be absent).', params: {} },
  { name: 'asa_campaigns', endpoint: 'asa', description: 'Live Apple Search Ads campaign/adgroup/keyword view. Returns asa_not_connected if no ASA org is linked yet.', params: {} },
  { name: 'asa_connect', endpoint: 'asa/connect', method: 'POST',
    description: 'Connect an Apple Search Ads org to this account. Pass keyPemPath (local path to the .p8 private key file) — the file is read locally and sent once over HTTPS; it is never logged or stored on disk by this tool. Credentials are verified against Apple before being stored encrypted server-side. Returns asa_already_connected unless overwrite is true.',
    params: { clientId: { ...str, required: true }, teamId: { ...str, required: true }, keyId: { ...str, required: true }, orgId: { ...str, required: true }, keyPemPath: { ...str, required: true }, campaignId: str, overwrite: { type: 'boolean' } } },
];

function toolSchema(t) {
  const properties = {};
  const required = [];
  for (const [k, v] of Object.entries(t.params)) {
    const { required: req, ...schema } = v;
    properties[k] = schema;
    if (req) required.push(k);
  }
  return {
    name: t.name,
    description: t.description,
    inputSchema: { type: 'object', properties, ...(required.length ? { required } : {}) },
  };
}

async function callTool(name, args) {
  const t = TOOLS.find((x) => x.name === name);
  if (!t) throw new Error('unknown tool: ' + name);
  const a = args || {};
  let path = t.endpoint;
  const qs = new URLSearchParams();
  for (const k of Object.keys(t.params)) {
    if (a[k] === undefined || a[k] === null || a[k] === '') continue;
    if (path.includes('{' + k + '}')) path = path.replace('{' + k + '}', encodeURIComponent(String(a[k])));
    else qs.set(k, String(a[k]));
  }
  if (path.includes('{')) throw new Error('missing required argument for ' + name);
  if (t.method === 'POST') {
    for (const k of Object.keys(t.params)) {
      if (t.params[k].required && (a[k] === undefined || a[k] === null || a[k] === '')) {
        throw new Error('missing required argument ' + k + ' for ' + name);
      }
    }
    const body = { ...a };
    if (name === 'asa_connect') {
      const fs = require('fs');
      let pem;
      try { pem = fs.readFileSync(String(a.keyPemPath), 'utf8'); }
      catch (e) { throw new Error('could not read keyPemPath: ' + e.message); }
      if (!/-----BEGIN [A-Z ]*PRIVATE KEY-----/.test(pem)) throw new Error('keyPemPath does not look like a .p8 private key (PEM)');
      delete body.keyPemPath;
      body.keyPem = pem;
    }
    const resP = await fetch(BASE + '/api/agent/' + path, {
      method: 'POST',
      headers: { 'x-api-key': API_KEY, 'Content-Type': 'application/json' },
      body: JSON.stringify(body),
    });
    const textP = await resP.text();
    if (!resP.ok && resP.status !== 400) throw new Error('HTTP ' + resP.status + ': ' + textP.slice(0, 300));
    return textP;
  }
  const url = BASE + '/api/agent/' + path + (qs.toString() ? '?' + qs.toString() : '');
  const res = await fetch(url, { headers: { 'x-api-key': API_KEY } });
  const text = await res.text();
  if (!res.ok && res.status !== 400) throw new Error('HTTP ' + res.status + ': ' + text.slice(0, 300));
  return text;
}

// ---- minimal JSON-RPC 2.0 over stdio (newline-delimited) ----

function send(msg) {
  process.stdout.write(JSON.stringify(msg) + '\n');
}

function reply(id, result) { send({ jsonrpc: '2.0', id, result }); }
function replyErr(id, code, message) { send({ jsonrpc: '2.0', id, error: { code, message } }); }

async function handle(msg) {
  const { id, method, params } = msg;
  if (method === 'initialize') {
    return reply(id, {
      protocolVersion: (params && params.protocolVersion) || '2025-06-18',
      capabilities: { tools: {} },
      serverInfo: { name: 'searchads-mcp', version: '0.2.2' },
    });
  }
  if (method === 'notifications/initialized' || (method && method.startsWith('notifications/'))) return; // no reply to notifications
  if (method === 'ping') return reply(id, {});
  if (method === 'tools/list') return reply(id, { tools: TOOLS.map(toolSchema) });
  if (method === 'tools/call') {
    try {
      const text = await callTool(params.name, params.arguments);
      return reply(id, { content: [{ type: 'text', text }], isError: false });
    } catch (e) {
      return reply(id, { content: [{ type: 'text', text: String(e.message || e) }], isError: true });
    }
  }
  if (id !== undefined) replyErr(id, -32601, 'method not found: ' + method);
}

let buf = '';
let pending = 0;
let stdinClosed = false;
function maybeExit() { if (stdinClosed && pending === 0) process.exit(0); }

process.stdin.setEncoding('utf8');
process.stdin.on('data', (chunk) => {
  buf += chunk;
  let idx;
  while ((idx = buf.indexOf('\n')) >= 0) {
    const line = buf.slice(0, idx).trim();
    buf = buf.slice(idx + 1);
    if (!line) continue;
    let msg;
    try { msg = JSON.parse(line); } catch { continue; }
    pending++;
    Promise.resolve(handle(msg))
      .catch((e) => {
        if (msg.id !== undefined) replyErr(msg.id, -32603, String(e.message || e));
      })
      .finally(() => { pending--; maybeExit(); });
  }
});
process.stdin.on('end', () => { stdinClosed = true; maybeExit(); });
