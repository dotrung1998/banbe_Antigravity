// @ts-check
import { defineConfig, devices } from '@playwright/test';

// Specs for PUBLIC pages only (no account): no global sign-in, no stored session, nothing written anywhere.
// Run: npx playwright test -c playwright.public.config.js
export default defineConfig({
  testDir: './tests/public',
  fullyParallel: true,
  reporter: 'list',
  use: { baseURL: 'http://localhost:5199', trace: 'off' },
  projects: [{ name: 'chromium', use: { ...devices['Desktop Chrome'] } }],
  // Own port, never reused: a dev server already on 5173 may be serving a different checkout.
  webServer: { command: 'npm run dev -- --port 5199 --strictPort', url: 'http://localhost:5199', reuseExistingServer: false },
});
