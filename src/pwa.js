/**
 * Service worker registration with explicit update handling.
 *
 * The previous setup relied on vite-plugin-pwa's auto-injected register script,
 * which only calls navigator.serviceWorker.register() once and never asks for an
 * update. An installed PWA is usually resumed rather than reloaded, so it could
 * stay on a stale build indefinitely.
 *
 * Here we register explicitly and check for a new worker whenever the app comes
 * back to the foreground, which is exactly the moment a phone user reopens it.
 */

let applyUpdate = null;

const settle = (worker) => new Promise((resolve) => {
  if (!worker) return resolve(null);
  if (['installed', 'activated', 'redundant'].includes(worker.state)) return resolve(worker);
  worker.addEventListener('statechange', () => {
    if (['installed', 'activated', 'redundant'].includes(worker.state)) resolve(worker);
  });
});

export const initServiceWorker = () => {
  if (typeof navigator === 'undefined' || !('serviceWorker' in navigator)) return;

  // Only auto-reload if this page was already controlled. On a first visit the
  // controller arrives for the first time and a reload would be pointless.
  const hadController = Boolean(navigator.serviceWorker.controller);
  navigator.serviceWorker.addEventListener('controllerchange', () => {
    if (hadController) window.location.reload();
  });

  import('virtual:pwa-register')
    .then(({ registerSW }) => {
      applyUpdate = registerSW({
        immediate: true,
        onNeedRefresh() {
          // autoUpdate mode activates the new worker by itself; the page still
          // needs a reload to pick up the new assets.
          applyUpdate?.(true);
        }
      });
    })
    .catch(() => {
      /* offline support is optional; the app works without it */
    });

  document.addEventListener('visibilitychange', () => {
    if (document.visibilityState === 'visible') checkForUpdate();
  });

  // Long sessions happen; check hourly while the app stays open.
  setInterval(checkForUpdate, 60 * 60 * 1000);
};

/**
 * Ask the browser for a new worker, activate it, and reload if anything changed.
 * Returns 'updated' | 'current' | 'unsupported'.
 */
export const checkForUpdate = async () => {
  if (typeof navigator === 'undefined' || !('serviceWorker' in navigator)) return 'unsupported';

  try {
    const registration = await navigator.serviceWorker.getRegistration();
    if (!registration) return 'unsupported';

    // update() fetches the worker script with the HTTP cache bypassed, so a
    // stale GitHub Pages cache cannot hide a new build.
    await registration.update();

    const pending = registration.waiting || registration.installing;
    if (!pending) return 'current';

    // update() resolves before a new worker finishes installing, so wait for it
    // to reach installed/activated instead of assuming it is ready.
    const settled = await settle(pending);
    if (!settled || settled.state === 'redundant') return 'current';

    pending.postMessage({ type: 'SKIP_WAITING' });
    applyUpdate?.(true);
    return 'updated';
  } catch {
    return 'unsupported';
  }
};

export const reload = () => window.location.reload();
