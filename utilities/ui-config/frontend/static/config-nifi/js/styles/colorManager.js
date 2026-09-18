/**
 * colorManager.js
 * ----------------------------------------------------------------------
 * Single source of truth for category → visual styling mapping used by
 * the "Valid NiFi 2 Flows (Host)" tree and any other flow-category UI.
 *
 * BUG FIX (previously in `getFlowCategory`):
 *   Root-level files (no subfolder) were tagged with the `root-badge`
 *   CSS class (green, #34d399) for the *badge text*, but the wrapping
 *   *button* was given `btn-feature` — the same button chrome used by the
 *   "Feature" category. That made Root and Feature items visually identical
 *   except for the badge text color, i.e. Feature's color identity bled
 *   into Root rows right next to the folder name.
 *
 *   Fix: introduce a dedicated `.btn-root` class whose accent matches
 *   `.root-badge`, and have ROOT_CATEGORY use it instead of CORE's.
 * ----------------------------------------------------------------------
 */

/**
 * @typedef {Object} CategoryStyle
 * @property {string} label       Display label (e.g. "Core")
 * @property {string} badgeClass  CSS class for the small badge span
 * @property {string} btnClass    CSS class for the wrapping action button
 */

/** Known folder→category mapping. Extend here as new conventions appear. */
export const FOLDER_CATEGORY_MAP = Object.freeze({
  // Features NiFi components
  features:        { label: 'Features',       badgeClass: 'features-badge',     btnClass: 'btn-feature' },
  
  // Tutorial / Learning flows
  tutorial:    { label: 'Tutorial',   badgeClass: 'tutorial-badge', btnClass: 'btn-tutorial' },
  
  // User customized flows
  customize:   { label: 'User',       badgeClass: 'user-badge',     btnClass: 'btn-user-flow' },
  
  // Based NiFi flows (new)
  'based-nifi': { label: 'Based NiFi', badgeClass: 'based-badge',   btnClass: 'btn-based' },
});

/** Category used for files that sit directly at the scan root (no folder). */
export const ROOT_CATEGORY = Object.freeze({
  label: 'Root',
  badgeClass: 'root-badge',
  // FIX: was 'btn-feature' — Root now gets its own button styling so its
  // green badge identity isn't masked by Core's blue button chrome.
  btnClass: 'btn-root',
});

/**
 * Generic styling for a folder name that isn't a known category.
 * @param {string} folderName
 * @returns {CategoryStyle}
 */
export function getFolderBadge(folderName) {
  const key = String(folderName || '').toLowerCase().trim();

  // Exact match first (fast path)
  if (FOLDER_CATEGORY_MAP[key]) return FOLDER_CATEGORY_MAP[key];

  // Smart matching for common variations (plural, typos, etc.)
  for (const [mapKey, style] of Object.entries(FOLDER_CATEGORY_MAP)) {
    if (key === mapKey || 
        key === mapKey + 's' ||           // cores → core
        key === mapKey + 'es' ||          // tutorials → tutorial
        key.includes(mapKey) ||           // based-nifi contains nothing, but customize would
        key.startsWith(mapKey)) {
      return style;
    }
  }

  // Fallback: generic folder badge (gray)
  const label = folderName.replace(/[-_]/g, ' ').replace(/\b\w/g, (c) => c.toUpperCase());
  return { label, badgeClass: 'folder-badge', btnClass: 'btn-folder' };
}

/**
 * Split an absolute path into segments relative to a scanned root folder.
 * @param {string} path
 * @param {string} root
 * @returns {string[]}
 */
export function getRelativeSegments(path, root) {
  let p = String(path || '').replace(/\\/g, '/');
  let r = String(root || '/').replace(/\\/g, '/');
  if (!r.endsWith('/')) r += '/';
  p = p.startsWith(r) ? p.slice(r.length) : p.replace(/^\/+/, '');
  return p.split('/').filter(Boolean);
}

/**
 * Resolve the visual category for a single flow file by walking its
 * folder path from deepest to shallowest, looking for a known category
 * name. Falls back to its immediate parent folder, then to ROOT_CATEGORY.
 * @param {string} path
 * @param {string} scanRoot
 * @returns {CategoryStyle}
 */
export function getFlowCategory(path, scanRoot) {
  const segments = getRelativeSegments(path, scanRoot);
  const folderSegments = segments.slice(0, -1);

  for (let i = folderSegments.length - 1; i >= 0; i--) {
    const seg = folderSegments[i].toLowerCase();
    if (FOLDER_CATEGORY_MAP[seg]) {
      return FOLDER_CATEGORY_MAP[seg];
    }
    // Smart matching for common variations
    for (const [mapKey, style] of Object.entries(FOLDER_CATEGORY_MAP)) {
      if (seg === mapKey || seg === mapKey + 's' || seg === mapKey + 'es' || seg.includes(mapKey)) {
        return style;
      }
    }
  }

  if (folderSegments.length === 0) {
    return ROOT_CATEGORY;
  }

  return getFolderBadge(folderSegments[folderSegments.length - 1]);
}
