import { defineConfig, type ESBuildOptions } from 'vite';
import RubyPlugin from 'vite-plugin-ruby';

export default defineConfig(() => {
  const isStorybook = process.argv.some((arg: string) => arg.includes('storybook'));

  return {
    plugins: [
      !isStorybook && RubyPlugin(),
    ].filter(Boolean),
    esbuild: {
      jsx: 'automatic',
    } as ESBuildOptions,
    base: isStorybook ? './' : undefined,
  };
});
