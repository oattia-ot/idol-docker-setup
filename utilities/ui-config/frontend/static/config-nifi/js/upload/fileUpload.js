import { showAlert } from '../core/notifications.js';
import { loadHostFolderFlows } from '../flows/hostFlows.js';

const ALLOWED_EXTENSIONS = ['.json', '.xml', '.flow', '.template'];

function getExt(filename) {
  return '.' + filename.split('.').pop().toLowerCase();
}

export function triggerFileUpload() {
  console.log('[UPLOAD] Trigger file upload dialog');
  const input = document.createElement('input');
  input.type = 'file';
  input.accept = ALLOWED_EXTENSIONS.join(',');
  input.onchange = (event) => {
    const file = event.target.files[0];
    if (file) uploadFile(file);
  };
  input.click();
}

export async function uploadFile(file) {
  if (!file) return;
  const ext = getExt(file.name);
  if (!ALLOWED_EXTENSIONS.includes(ext)) {
    showAlert(`File type not allowed. Use: ${ALLOWED_EXTENSIONS.join(', ')}`, 'error');
    return;
  }

  console.log(`[UPLOAD] Selected file: ${file.name}`);
  const formData = new FormData();
  formData.append('file', file);

  const btn = document.querySelector('#hostConfig .btn-secondary');
  const originalHtml = btn ? btn.innerHTML : '';
  if (btn) { btn.innerHTML = '<i class="fas fa-spinner fa-spin"></i> Uploading...'; btn.disabled = true; }

  try {
    const response = await fetch('/config-nifi/api/upload-flow', { method: 'POST', body: formData });
    const data = await response.json();
    if (data.success) {
      showAlert(`✅ ${data.message}`, 'success');
      loadHostFolderFlows();
    } else {
      showAlert(`❌ Upload failed: ${data.error}`, 'error');
    }
  } catch (err) {
    showAlert(`Upload error: ${err.message}`, 'error');
  } finally {
    if (btn) { btn.innerHTML = originalHtml; btn.disabled = false; }
  }
}

/** Wire up drag & drop zone listeners. Call once on init. */
export function initUploadDropZone() {
  const zone = document.getElementById('uploadZoneContainer');
  const fileInput = document.getElementById('fileInput');

  if (zone) {
    console.log('[UPLOAD] Drag & drop zone initialized');
    zone.addEventListener('click', (e) => {
      if (e.target.closest('label') || e.target.id === 'fileInput') return;
      fileInput?.click();
    });
    zone.addEventListener('dragover', (e) => {
      e.preventDefault();
      zone.style.borderColor = '#0d6efd';
      zone.style.backgroundColor = 'rgba(13, 110, 253, 0.1)';
    });
    zone.addEventListener('dragleave', () => {
      zone.style.borderColor = '#475569';
      zone.style.backgroundColor = '#1e2937';
    });
    zone.addEventListener('drop', (e) => {
      e.preventDefault();
      zone.style.borderColor = '#475569';
      zone.style.backgroundColor = '#1e2937';
      const file = e.dataTransfer.files[0];
      if (file) uploadFile(file);
    });
  }

  if (fileInput) {
    fileInput.addEventListener('change', (e) => {
      if (e.target.files[0]) uploadFile(e.target.files[0]);
    });
  }
}
