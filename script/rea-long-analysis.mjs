// REA 6.0.0 has a fixed 330-second Ghidra import/analysis deadline. This optional
// project-local loader extends only that deadline for the large FL engine.
// No installed package or global configuration is modified. Auto-analysis and
// Evidence generation are unchanged. Use with Node 24.11+ --import.
import { registerHooks } from 'node:module';

const duration = Number(process.env.VL_GHIDRA_STARTUP_MS || 1200000);
if (!Number.isInteger(duration) || duration < 330000 || duration > 1800000) {
  throw new Error('VL_GHIDRA_STARTUP_MS must be an integer from 330000 to 1800000');
}
registerHooks({
  load(url, context, nextLoad) {
    const result = nextLoad(url, context);
    if (url.endsWith('/rea-agents/dist/ghidra/GhidraDefaults.js')) {
      const original = String(result.source);
      const expected = 'export const GHIDRA_STARTUP_TIMEOUT_MS = 330_000;';
      if (!original.includes(expected)) throw new Error('Unexpected REA deadline module; refusing patch');
      return { ...result, source: original.replace(expected, `export const GHIDRA_STARTUP_TIMEOUT_MS = ${duration};`) };
    }
    return result;
  },
});
