import { NIFI_RETRY_SECS } from '../config/constants.js';
import { state } from '../core/state.js';

function stopNiFiRetry() {
  if (!state.nifiRetryTimer) return;
  clearInterval(state.nifiRetryTimer);
  state.nifiRetryTimer = null;
  console.log('[NIFI POLL] Retry timer stopped');
}

function startNiFiRetry(reason, isHard = false) {
  stopNiFiRetry();

  let secondsLeft = NIFI_RETRY_SECS;
  const colour = isHard
    ? { bg: 'var(--danger-glow)', text: 'var(--danger)', border: '1px solid rgba(239,68,68,.3)' }
    : { bg: 'var(--warning-glow)', text: 'var(--warning)', border: '1px solid rgba(245,158,11,.3)' };

  const render = (sec) => {
    const b = document.getElementById('nifiApiStatusBadge');
    if (!b) return;
    b.innerHTML = `
        <i class="fas fa-times-circle"></i>
        ${reason}
        <span style="margin-left:6px;font-size:10px;opacity:.7;
                    background:rgba(0,0,0,.25);padding:1px 6px;
                    border-radius:9999px;font-variant-numeric:tabular-nums;">
        ↻&nbsp;${sec}s
        </span>`;
    b.style.background = colour.bg;
    b.style.color = colour.text;
    b.style.border = colour.border;
  };

  render(secondsLeft);

  state.nifiRetryTimer = setInterval(() => {
    secondsLeft -= 1;
    if (secondsLeft <= 0) {
      clearInterval(state.nifiRetryTimer);
      state.nifiRetryTimer = null;
      console.log('[NIFI POLL] Countdown reached 0 — retrying...');
      checkNiFiApiStatus();
    } else {
      render(secondsLeft);
    }
  }, 1000);

  console.log(`[NIFI POLL] Retry countdown started (${reason})`);
}

function setTestButtonState(reachable) {
  const btn = document.getElementById('testNiFiBtn');
  if (!btn) return;
  btn.disabled = !reachable;
  btn.title = reachable ? 'NiFi API is reachable — ready to test connection' : 'NiFi API must be reachable first';
  btn.style.opacity = reachable ? '1' : '0.45';
  btn.style.cursor = reachable ? 'pointer' : 'not-allowed';
}

export async function checkNiFiApiStatus() {
  const badge = document.getElementById('nifiApiStatusBadge');
  const nifiApiUrl = document.getElementById('nifiApiUrl')?.value?.trim();

  if (!badge) return;

  if (!nifiApiUrl) {
    stopNiFiRetry();
    badge.innerHTML = `<i class="fas fa-exclamation-circle"></i> No URL set`;
    badge.style.background = 'rgba(245,158,11,.12)';
    badge.style.color = 'var(--warning)';
    badge.style.border = '1px solid rgba(245,158,11,.3)';
    setTestButtonState(false);
    return;
  }

  badge.innerHTML = `<i class="fas fa-spinner fa-spin"></i> Checking...`;
  badge.style.background = 'rgba(148,163,184,.1)';
  badge.style.color = 'var(--text-muted)';
  badge.style.border = '1px solid var(--border)';
  setTestButtonState(false);

  try {
    const response = await fetch('/config-idol/check-nifi', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ url: nifiApiUrl }),
    });

    const data = await response.json();

    if (data.success && data.reachable) {
      stopNiFiRetry();
      badge.innerHTML = `<i class="fas fa-check-circle"></i> Reachable`;
      badge.style.background = 'var(--success-glow)';
      badge.style.color = 'var(--success)';
      badge.style.border = '1px solid rgba(16,185,129,.3)';
      setTestButtonState(true);
    } else {
      startNiFiRetry(data.message || 'Unreachable', false);
      setTestButtonState(false);
    }
  } catch {
    startNiFiRetry('Connection refused', true);
    setTestButtonState(false);
  }
}

export function debouncedNiFiCheck() {
  clearTimeout(state.nifiCheckTimer);
  state.nifiCheckTimer = setTimeout(checkNiFiApiStatus, 800);
}
