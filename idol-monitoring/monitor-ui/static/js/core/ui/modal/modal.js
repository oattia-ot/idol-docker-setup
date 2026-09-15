/**
 * Simple modal dialog
 */

let currentModal = null;

export function showModal(title, bodyHtml, options = {}) {
  closeModal(); // only one at a time

  const overlay = document.createElement('div');
  overlay.style.cssText = `
    position: fixed; inset: 0; background: rgba(15, 23, 42, 0.75);
    display: flex; align-items: center; justify-content: center; z-index: 99999;
  `;

  const modal = document.createElement('div');
  modal.style.cssText = `
    background: #1e293b; border: 1px solid #334155; border-radius: 12px;
    width: min(92%, 520px); box-shadow: 0 25px 50px -12px rgb(0 0 0 / 0.4);
    overflow: hidden;
  `;

  modal.innerHTML = `
    <div style="padding: 1rem 1.5rem; border-bottom: 1px solid #334155; display:flex; justify-content:space-between; align-items:center;">
      <h3 style="margin:0; font-size:1.1rem;">${title}</h3>
      <button class="modal-close" style="background:none;border:none;color:#94a3b8;font-size:1.5rem;cursor:pointer;line-height:1;">×</button>
    </div>
    <div style="padding: 1.5rem;">
      ${bodyHtml}
    </div>
    <div style="padding: 1rem 1.5rem; background:#0f172a; display:flex; justify-content:flex-end; gap:0.5rem;">
      <button class="btn-cancel" style="padding:0.5rem 1rem; border-radius:6px; border:1px solid #334155; background:transparent; color:#e2e8f0; cursor:pointer;">Close</button>
    </div>
  `;

  overlay.appendChild(modal);
  document.body.appendChild(overlay);
  currentModal = overlay;

  // Close handlers
  const closeBtn = modal.querySelector('.modal-close');
  const cancelBtn = modal.querySelector('.btn-cancel');

  const closeHandler = () => closeModal();
  closeBtn.addEventListener('click', closeHandler);
  cancelBtn.addEventListener('click', closeHandler);
  overlay.addEventListener('click', (e) => {
    if (e.target === overlay) closeModal();
  });

  // Optional onClose callback
  if (typeof options.onClose === 'function') {
    overlay._onClose = options.onClose;
  }
}

export function closeModal() {
  if (currentModal) {
    if (currentModal._onClose) currentModal._onClose();
    currentModal.remove();
    currentModal = null;
  }
}
