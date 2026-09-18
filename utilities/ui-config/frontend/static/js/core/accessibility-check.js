/**
 * accessibility-check.js
 * Reusable, production-grade utility for pre-navigation page accessibility / reachability checks.
 *
 * Used to guard navigation to monitoring tools, config pages, or any external/internal resource.
 * Prevents users from opening dead links or getting blank/error pages.
 *
 * @module core/accessibility-check
 */

/**
 * Check if a page/endpoint is accessible (responds successfully).
 *
 * Strategy:
 * 1. Attempt lightweight HEAD request (faster, less bandwidth).
 * 2. On failure (CORS, method not allowed, network error) fall back to GET with short body.
 * 3. Enforce hard timeout (default 7s) via AbortController.
 * 4. Only return true for HTTP 2xx responses.
 *
 * @param {string} url - Absolute or relative URL to check.
 * @param {number} [timeoutMs=7000] - Max wait time in milliseconds.
 * @returns {Promise<boolean>} true if page is reachable and returns 2xx, false otherwise.
 *
 * Edge cases handled:
 * - Network offline / DNS failure
 * - CORS blocked responses (falls back gracefully)
 * - Timeouts (AbortError)
 * - 3xx redirects (fetch follows them by default; final status checked)
 * - 4xx / 5xx → false
 * - Non-HTTP errors → false
 */
export async function isPageAccessible(url, timeoutMs = 7000) {
  if (!url || typeof url !== 'string') {
    console.error('[Accessibility] Invalid URL provided to isPageAccessible');
    return false;
  }

  const controller = new AbortController();
  const timeoutId = setTimeout(() => controller.abort(), timeoutMs);

  try {
    // 1. Try HEAD (preferred for speed)
    let res;
    try {
      res = await fetch(url, {
        method: 'HEAD',
        signal: controller.signal,
        cache: 'no-cache',
        mode: 'cors',
        credentials: 'same-origin'
      });
    } catch (headError) {
      // HEAD failed (common for some servers or CORS). Fallback to GET.
      // We only read status, not body, so it's still lightweight.
      res = await fetch(url, {
        method: 'GET',
        signal: controller.signal,
        cache: 'no-cache',
        headers: {
          'Pragma': 'no-cache',
          'Cache-Control': 'no-cache'
        },
        mode: 'cors',
        credentials: 'same-origin'
      });
    }

    clearTimeout(timeoutId);

    const ok = res.ok; // true for 200-299
    if (!ok) {
      console.warn(`[Accessibility] ${url} responded with status ${res.status}`);
    }
    return ok;

  } catch (err) {
    clearTimeout(timeoutId);

    if (err.name === 'AbortError') {
      console.warn(`[Accessibility] ⏱️ Timeout (${timeoutMs}ms) while checking ${url}`);
    } else if (err.message?.includes('Failed to fetch') || err.message?.includes('NetworkError')) {
      console.warn(`[Accessibility] 🌐 Network error checking ${url}:`, err.message);
    } else {
      console.warn(`[Accessibility] ❌ Error checking ${url}:`, err.message || err);
    }

    return false;
  }
}

/**
 * Convenience wrapper that also returns a user-friendly reason on failure.
 * Useful for showing precise toast messages.
 *
 * @param {string} url
 * @param {number} timeoutMs
 * @returns {Promise<{ accessible: boolean, reason?: string }>}
 */
export async function checkPageAccessibility(url, timeoutMs = 7000) {
  const accessible = await isPageAccessible(url, timeoutMs);
  if (accessible) {
    return { accessible: true };
  }
  return {
    accessible: false,
    reason: 'The page could not be reached. It may be temporarily down, misconfigured, or the service is not running.'
  };
}

console.log('%c[Accessibility] ✅ accessibility-check.js loaded (reusable isPageAccessible ready)', 'color:#10b981');