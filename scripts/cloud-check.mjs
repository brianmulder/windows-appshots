import { spawnSync } from 'node:child_process';
import { fileURLToPath } from 'node:url';

// Existing synthetic contracts only. Windows watcher/native tests remain in npm test.
const names = [
  'advertises the complete appshot tool surface',
  'initializes with MCP tool capabilities',
  'returns a saved bundle as text plus image',
  'refuses semantic retrieval from a legacy unverified bundle',
  'lists legacy bundles without unchecked semantic metadata',
  'rejects a latest-capture pointer outside the capture store',
  'plugin advertises persisted AppShots instead of live computer use',
];
const root = fileURLToPath(new URL('../', import.meta.url));
const result = spawnSync(process.execPath, [
  '--test', '--test-name-pattern', `^(?:${names.join('|')})$`,
  'tests/server.test.mjs', 'tests/plugin-boundary.test.mjs',
], { cwd: root, stdio: 'inherit' });
if (result.error) throw result.error;
process.exitCode = result.status ?? 1;
