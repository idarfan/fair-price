import js from '@eslint/js'
import tseslint from 'typescript-eslint'
import reactHooks from 'eslint-plugin-react-hooks'

export default tseslint.config(
  js.configs.recommended,
  ...tseslint.configs.recommended,
  {
    plugins: {
      'react-hooks': reactHooks,
    },
    rules: {
      ...reactHooks.configs.recommended.rules,
      // Catch common issues from our lessons
      'react-hooks/rules-of-hooks': 'error',
      'react-hooks/exhaustive-deps': 'warn',
      // set-state-in-effect: loading/error resets at effect start are intentional
      'react-hooks/set-state-in-effect': 'warn',
      // No any
      '@typescript-eslint/no-explicit-any': 'error',
      // Force explicit return types on public functions
      '@typescript-eslint/explicit-module-boundary-types': 'off',
    },
    files: ['app/frontend/**/*.{ts,tsx}', 'stories/**/*.{ts,tsx}'],
  },
  {
    ignores: [
      'node_modules/**',
      'public/**',
      'stories/Configure.mdx',
      'stories/Button.jsx',
      'stories/Header.jsx',
      'stories/Page.jsx',
    ],
  },
)
