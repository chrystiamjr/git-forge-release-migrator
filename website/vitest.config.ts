import path from 'node:path';
import { defineConfig } from 'vitest/config';

export default defineConfig({
  test: {
    environment: 'jsdom',
    setupFiles: ['./test/setup.ts'],
    globals: true,
    include: ['./test/**/*.test.ts?(x)'],
  },
  resolve: {
    alias: {
      '@site': path.resolve(__dirname),
      '@theme': path.resolve(__dirname, 'src/theme'),
      '@docusaurus': path.resolve(__dirname, 'test/mocks/docusaurus'),
    },
  },
});
