// Project-local REA MCP client. Keeps one native analysis session open and retains
// complete tool responses on disk. Input: one JSON command per line.
import { spawn } from 'node:child_process';
import { createInterface } from 'node:readline';
import { mkdir, writeFile } from 'node:fs/promises';
import { resolve } from 'node:path';

const destination = resolve(process.argv[2] || 'analysis/native');
await mkdir(destination, { recursive: true });
const child = spawn('npx', ['-y', 'rea-agents@6.0.0', 'mcp'], {
  env: process.env, stdio: ['pipe', 'pipe', 'pipe'],
});
let sequence = 0;
const pending = new Map();
child.stderr.on('data', data => process.stderr.write(data));
createInterface({ input: child.stdout }).on('line', line => {
  let message;
  try { message = JSON.parse(line); } catch { process.stderr.write(line + '\n'); return; }
  if (!message.id) return;
  const request = pending.get(message.id);
  if (!request) return;
  pending.delete(message.id);
  clearTimeout(request.timeout);
  if (message.error) request.reject(new Error(JSON.stringify(message.error)));
  else request.resolve(message.result);
});
child.on('exit', code => {
  for (const { reject, timeout } of pending.values()) {
    clearTimeout(timeout); reject(new Error(`REA exited: ${code}`));
  }
  process.exitCode = code || 0;
});
function rpc(method, params) {
  const id = ++sequence;
  return new Promise((resolve, reject) => {
    const timeout = setTimeout(() => {
      pending.delete(id); reject(new Error(`REA request timed out: ${method}`));
    }, Math.max(720000, Number(process.env.VL_GHIDRA_STARTUP_MS || 330000) + 120000));
    pending.set(id, { resolve, reject, timeout });
    child.stdin.write(JSON.stringify({ jsonrpc: '2.0', id, method, params }) + '\n');
  });
}
await rpc('initialize', {
  protocolVersion: '2024-11-05', capabilities: {},
  clientInfo: { name: 'veggie-loops-investigation', version: '0.1.0' },
});
child.stdin.write(JSON.stringify({ jsonrpc: '2.0', method: 'notifications/initialized' }) + '\n');
const catalog = await rpc('tools/list', {});
await writeFile(resolve(destination, 'tool-catalog.json'), JSON.stringify(catalog, null, 2));
console.log(JSON.stringify({ ready: true, tools: catalog.tools.map(tool => tool.name) }));

const input = createInterface({ input: process.stdin });
for await (const line of input) {
  if (!line.trim()) continue;
  try {
    const command = JSON.parse(line);
    if (command.exit) { input.close(); child.stdin.end(); break; }
    if (command.schema) {
      console.log(JSON.stringify(catalog.tools.filter(tool => command.schema.includes(tool.name)), null, 2));
      continue;
    }
    console.log(JSON.stringify({ started: command.name, time: new Date().toISOString() }));
    const result = await rpc('tools/call', { name: command.name, arguments: command.arguments || {} });
    const filename = (command.save || `${sequence}-${command.name}`) + '.json';
    await writeFile(resolve(destination, filename), JSON.stringify(result, null, 2));
    let structured = result.structuredContent;
    if (!structured) {
      const text = result.content?.find(item => item.type === 'text')?.text;
      try { structured = JSON.parse(text); } catch { structured = text; }
    }
    console.log(JSON.stringify({ completed: command.name, saved: resolve(destination, filename), isError: result.isError, summary: command.full ? structured : typeof structured === 'string' ? structured.slice(0, 1500) : structured && { keys: Object.keys(structured), error: structured.error, evidence_id: structured.evidence_id, result: structured.result && (typeof structured.result === 'string' ? { characters: structured.result.length } : Array.isArray(structured.result) ? { count: structured.result.length } : { keys: Object.keys(structured.result) }) } }));
  } catch (error) { console.log(JSON.stringify({ error: error.message })); }
}
