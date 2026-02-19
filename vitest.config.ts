import { defineConfig } from "vitest/config";
import react from "@vitejs/plugin-react";

export default defineConfig({
  plugins: [react()],
  test: {
    globals: true,
    environment: "happy-dom",
    setupFiles: ["./src/test/setup.ts"],
    css: true,
    exclude: ["**/node_modules/**", "**/dist/**", "**/.worktrees/**", "**/e2e/**"],
    coverage: {
      reporter: ["text", "json", "html"],
    },
  },
});
