/**
 * core/ui/modal/modal.js
 * Generic open/close modal helper. Replaces bespoke
 * openModal/closeModal/showCmd/closeCmdModal pairs that were
 * re-implemented per page.
 */

export function openModal(id) {
  const el = document.getElementById(id);
  if (el) el.classList.add('open');
}

export function closeModal(id) {
  const el = document.getElementById(id);
  if (el) el.classList.remove('open');
}

/** Close the modal only when the click landed on the backdrop itself. */
export function closeModalOnBackdropClick(event, id) {
  if (event.target.id === id) closeModal(id);
}
