import { defineConfig, devices } from '@playwright/test';
import { readFileSync } from 'node:fs';
const REPO = process.env.E2E_REPO;
const OUT = process.env.E2E_OUT_DIR;
const focused = readFileSync(new URL('./focused-specs.txt', import.meta.url), 'utf8').split('\n').map((s) => s.trim()).filter(Boolean);
// Second, independent fail-closed layer: hosted Supabase/R2/Cloudflare names do not resolve in the browser.
const args = ['--host-resolver-rules=MAP *.supabase.co ~NOTFOUND, MAP *.supabase.in ~NOTFOUND, MAP *.r2.cloudflarestorage.com ~NOTFOUND, MAP *.r2.dev ~NOTFOUND, MAP api.cloudflare.com ~NOTFOUND'];
const desktop = { ...devices['Desktop Chrome'], launchOptions: { args } };
export default defineConfig({
  globalSetup: new URL('./global-setup.mjs', import.meta.url).pathname,
  fullyParallel: false, workers: 1, retries: 0,
  reporter: [['list'], ['json', { outputFile: `${OUT}/result-${process.env.E2E_LABEL || 'run'}.json` }]],
  outputDir: `${OUT}/artifacts`,
  use: { baseURL: 'http://localhost:5199', storageState: process.env.E2E_STORAGE_STATE },
  projects: [
    { name: 'focused', testDir: `${REPO}/tests`, testMatch: focused.map((n) => new RegExp(`/${n}\\.spec\\.js$`)), use: desktop },
    { name: 'focused-copies', testDir: new URL('./focused-copies', import.meta.url).pathname, testMatch: /\.spec\.mjs$/, use: desktop }, // guard-safe copies of repo specs that bypass the harness (see file headers)
    { name: 'diag', testDir: new URL('./diag', import.meta.url).pathname, testMatch: /\.diag\.mjs$/, use: desktop }, // read-only probes against the local stack (focused env, R2 off)
    { name: 'r2', testDir: new URL('./specs', import.meta.url).pathname, testMatch: /\.spec\.mjs$/, use: desktop },
  ],
  webServer: [
    { command: 'node scripts/e2e-local/local-backend.mjs', url: 'http://127.0.0.1:59100/__calls', reuseExistingServer: false, cwd: REPO, timeout: 60000 },
    { command: './node_modules/.bin/vite --config scripts/e2e-local/vite.local.config.mjs --port 5199 --strictPort --host localhost', url: 'http://localhost:5199', reuseExistingServer: false, cwd: REPO, timeout: 120000 },
  ],
});
