import { defineConfig } from "astro/config";
import sitemap from "@astrojs/sitemap";

export default defineConfig({
  site: "https://jeremym.github.io",
  base: "/clipy-secure",
  output: "static",
  trailingSlash: "always",
  integrations: [sitemap()],
});
