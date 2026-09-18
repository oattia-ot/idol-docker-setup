/**
 * DOM utility helpers
 * Used across the monitor UI for safe element selection and event delegation.
 */

/**
 * Get a single element (querySelector wrapper)
 * @param {string|Element} selector - CSS selector or element
 * @param {ParentNode} [parent=document]
 * @returns {Element|null}
 */
export function getEl(selector, parent = document) {
  if (!selector) return null;
  if (typeof selector === 'string') {
    return parent.querySelector(selector);
  }
  return selector; // already an element
}

/**
 * Event delegation helper
 * @param {Element} parent
 * @param {string} eventType - e.g. 'click'
 * @param {string} selector - target selector
 * @param {(event: Event, target: Element) => void} handler
 */
export function delegate(parent, eventType, selector, handler) {
  if (!parent) return;

  parent.addEventListener(eventType, (event) => {
    const target = event.target.closest(selector);
    if (target && parent.contains(target)) {
      handler(event, target);
    }
  });
}
