import js from '@eslint/js'
import globals from 'globals'
import reactHooks from 'eslint-plugin-react-hooks'
import reactRefresh from 'eslint-plugin-react-refresh'
import { defineConfig, globalIgnores } from 'eslint/config'

export default defineConfig([
  globalIgnores(['dist']),
  {
    files: ['**/*.{js,jsx}'],
    extends: [
      js.configs.recommended,
      reactHooks.configs.flat.recommended,
      reactRefresh.configs.vite,
    ],
    languageOptions: {
      globals: globals.browser,
      parserOptions: { ecmaFeatures: { jsx: true } },
    },
    rules: {
      // This app seeds form state from localStorage and from the selected
      // exercise inside effects. That is the documented React escape hatch for
      // "sync with an external store", not a cascading-render bug, so the new
      // React 19 rule is too strict for this codebase.
      'react-hooks/set-state-in-effect': 'off',
    },
  },
])
