import { API_BASE } from '../config/constants.js';
import { getValue, setValue, openModal, closeModal } from '../core/domUtils.js';
import { showAlert, showToast } from '../core/notifications.js';
import { listParamContexts } from './paramContextsList.js';

export function showCreateParamContext() {
  setValue('paramContextName', '');
  setValue('paramContextDesc', '');

  const example = [{ name: 'Parameter Property Name', value: 'Parameter Property Value', sensitive: false, description: 'Parameter Property Description' }];
  setValue('paramContextParams', JSON.stringify(example, null, 2));
  openModal('createParamContext');
}

export async function createParamContext() {
  const name = getValue('paramContextName').trim();
  if (!name) {
    showAlert('Name is required', 'error');
    return;
  }

  let params = [];
  const paramInput = getValue('paramContextParams').trim();

  try {
    if (paramInput) {
      let parsed;
      try {
        parsed = JSON.parse(paramInput);
      } catch {
        const fixed = paramInput
          .replace(/,\s*([\]}])/g, '$1')
          .replace(/\/\/.*$/gm, '')
          .replace(/\/\*[\s\S]*?\*\//g, '');
        parsed = JSON.parse(fixed);
      }

      if (!Array.isArray(parsed)) {
        console.warn('[CREATE] Parameters was object → converting to array');
        parsed = typeof parsed === 'object' && parsed !== null ? Object.values(parsed) : [];
      }

      params = parsed
        .map((item) => {
          if (typeof item === 'string') return { name: item, value: '', sensitive: false, description: '' };
          if (typeof item !== 'object' || item === null) return null;
          const p = item.parameter || item;
          return { name: String(p.name || '').trim(), value: String(p.value || ''), sensitive: Boolean(p.sensitive), description: String(p.description || '') };
        })
        .filter((p) => p && p.name);
    }
  } catch (e) {
    console.error('JSON Parse Error:', e);
    showAlert('Invalid JSON in Parameters field.<br><small>Use valid array starting with <code>[</code> and ending with <code>]</code></small>', 'error');
    return;
  }

  console.log(`[CREATE] Final sending ${params.length} clean parameters for: ${name}`);

  const payload = { name, description: getValue('paramContextDesc').trim(), parameters: params };

  const res = await fetch(`${API_BASE}/parameter-contexts`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify(payload),
  });

  const data = await res.json();
  console.log('[SAVE] Backend response:', data);

  if (data.success) {
    console.log('✅ Success! Parameters saved:', data.param_count || params.length);
    showToast(`Parameter Context "${name}" Created Successfully`, 'var(--success)');
    closeModal('createParamContext');
    listParamContexts();
  } else {
    showAlert('Failed: ' + (data.error || 'Unknown error'), 'error');
  }
}
