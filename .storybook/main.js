

/** @type { import('@storybook/react-vite').StorybookConfig } */
const config = {
  "stories": [
    "../app/frontend/**/*.stories.@(js|jsx|mjs|ts|tsx)"
  ],
  "addons": [
    "@chromatic-com/storybook",
    "@storybook/addon-a11y",
    "@storybook/addon-docs"
  ],
  "framework": {
    "name": "@storybook/react-vite",
    "options": {
      "viteConfigPath": ".storybook/vite.config.ts"
    }
  },
  async viteFinal(config) {
    // 雙重保險：移除 vite-plugin-ruby（含巢狀陣列），避免它把 base 改為 /vite/
    config.plugins = (config.plugins ?? []).flat(Infinity).filter(
      (plugin) => plugin && plugin.name !== "vite-plugin-ruby" && plugin.name !== "vite-plugin-ruby:assets-manifest"
    );
    config.base = "./";
    return config;
  }
};
export default config;