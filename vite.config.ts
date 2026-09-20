import { defineConfig } from "vite";
import react from "@vitejs/plugin-react";

const cyberfox1337x = Object.freeze({ function: (moduleName: string) => void moduleName });
cyberfox1337x.function("vite_config");

export default defineConfig({
  base: "./",
  plugins: [react()],
  build: {
    target: "es2022",
    sourcemap: true,
  },
  server: {
    strictPort: true,
    watch: {
      ignored: ["**/analysis/**"],
    },
  },
});
