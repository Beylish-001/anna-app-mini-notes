import { defineConfig } from "vite";
import { resolve } from "path";

export default defineConfig({
  root: ".",
  base: "./",
  build: {
    outDir: "bundle",
    emptyOutDir: true,
    rollupOptions: {
      input: resolve(__dirname, "index.html"),
      external: ["/static/anna-apps/_sdk/latest/index.js"],
    },
  },
});
