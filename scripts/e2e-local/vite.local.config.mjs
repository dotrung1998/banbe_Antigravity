// Vite config for the local harness only: the app's own config + a proxy that sends /api/* to the local backend.
import { mergeConfig } from 'vite';
import base from '../../vite.config.js';
export default mergeConfig(typeof base === 'function' ? base({ mode: 'development', command: 'serve' }) : base, {
  server: { proxy: { '/api': { target: 'http://127.0.0.1:5198', changeOrigin: false } } },
});
