import { tool, runTool, VERSION } from './tool.js';

type Msg = { jsonrpc: '2.0'; id?: number | string | null; method?: string; params?: any };

/**
 * Minimal MCP server logic (JSON-RPC 2.0, tools only). Returns the response, or null for notifications.
 * Hand-written so the package stays dependency-free.
 */
export function handleMcp(msg: Msg): object | null {
  const reply = (result: object) => ({ jsonrpc: '2.0', id: msg.id, result });
  const isRequest = msg.id !== undefined && msg.id !== null;
  switch (msg.method) {
    case 'initialize':
      return reply({
        protocolVersion: typeof msg.params?.protocolVersion === 'string' ? msg.params.protocolVersion : '2025-06-18',
        capabilities: { tools: {} },
        serverInfo: { name: 'qrmotion', version: VERSION },
      });
    case 'ping':
      return reply({});
    case 'tools/list':
      return reply({ tools: [tool] });
    case 'tools/call': {
      if (msg.params?.name !== tool.name) return reply({ isError: true, content: [{ type: 'text', text: `unknown tool ${msg.params?.name}` }] });
      try {
        const out = runTool(msg.params?.arguments ?? {});
        const { output, ...meta } = out;
        return reply({ content: [{ type: 'text', text: output }, { type: 'text', text: JSON.stringify(meta) }] });
      } catch (e) {
        return reply({ isError: true, content: [{ type: 'text', text: (e as Error).message }] });
      }
    }
    default:
      return isRequest ? { jsonrpc: '2.0', id: msg.id, error: { code: -32601, message: `method not found: ${msg.method}` } } : null;
  }
}

/** Serve MCP over stdio (newline-delimited JSON). */
// structural types so the public .d.ts doesn't require @types/node
export function serveMcp(
  input: { on(event: 'data', cb: (chunk: string | Uint8Array) => void): unknown } = process.stdin,
  output: { write(s: string): unknown } = process.stdout,
) {
  let buf = '';
  const decoder = new TextDecoder();
  input.on('data', (chunk) => {
    buf += typeof chunk === 'string' ? chunk : decoder.decode(chunk, { stream: true });
    let nl;
    while ((nl = buf.indexOf('\n')) >= 0) {
      const line = buf.slice(0, nl).trim();
      buf = buf.slice(nl + 1);
      if (!line) continue;
      let res: object | null;
      try { res = handleMcp(JSON.parse(line)); } catch { res = { jsonrpc: '2.0', id: null, error: { code: -32700, message: 'parse error' } }; }
      if (res) output.write(JSON.stringify(res) + '\n');
    }
  });
}
