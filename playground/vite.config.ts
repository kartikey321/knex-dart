import { defineConfig } from 'vite';

export default defineConfig({
  server: {
    port: 5176,
  },
  optimizeDeps: {
    exclude: ['@electric-sql/pglite'],
  },
  worker: {
    format: 'es',
  },
});
