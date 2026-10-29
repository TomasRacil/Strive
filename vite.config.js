import { defineConfig } from 'vite'
import react from '@vitejs/plugin-react'
import { VitePWA } from 'vite-plugin-pwa'
import { execSync } from 'node:child_process'

// Stamp the build so the running app can show which version it is on. Without
// this there is no way to tell a stale cached PWA from a current one.
const buildId = (() => {
  if (process.env.GITHUB_SHA) return process.env.GITHUB_SHA.slice(0, 7)
  try {
    return execSync('git rev-parse --short HEAD').toString().trim()
  } catch {
    return 'dev'
  }
})()

// https://vitejs.dev/config/
export default defineConfig({
  // Project page lives at https://<user>.github.io/Strive/, not at the domain
  // root. Without a relative base every asset URL is emitted as /assets/...,
  // which 404s on Pages. './' also keeps working if the repo is renamed or a
  // custom domain is added later.
  base: './',
  define: {
    __BUILD_ID__: JSON.stringify(buildId)
  },
  plugins: [
    react(),
    VitePWA({
      registerType: 'autoUpdate',
      // Registration is done in src/pwa.js so updates can be checked and
      // applied deliberately instead of once on first load.
      injectRegister: false,
      includeAssets: ['favicon.ico', 'apple-touch-icon.png'],
      manifest: {
        name: 'Strive',
        short_name: 'Strive',
        description: 'Training tracker with Garmin sync',
        theme_color: '#050505',
        background_color: '#050505',
        display: 'standalone',
        start_url: './',
        scope: './',
        icons: [
          {
            src: 'pwa-192x192.png',
            sizes: '192x192',
            type: 'image/png'
          },
          {
            src: 'pwa-512x512.png',
            sizes: '512x512',
            type: 'image/png'
          },
          {
            src: 'pwa-512x512.png',
            sizes: '512x512',
            type: 'image/png',
            purpose: 'any maskable'
          }
        ]
      }
    })
  ],
})
