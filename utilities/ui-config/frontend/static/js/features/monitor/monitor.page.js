/**
 * features/monitor/monitor.page.js
 * Composition root for the monitor config page.
 * Replaces: frontend/static/config-monitor/js/monitor-config.js
 */

import { createMonitorStore } from './state/monitor-state.js';
import { renderMonitorGrid, renderUrlPanel } from './components/monitor-grid.js';
import { createToaster } from '../../core/ui/toast/toast.js';
import { openModal, closeModal, closeModalOnBackdropClick } from '../../core/ui/modal/modal.js';
import { delegate, getEl } from '../../core/ui/dom-utils.js';

const CMD_MODAL_ID = 'cmdModal';

export function initMonitorPage() {
  const store = createMonitorStore();
  const toast = createToaster('toastContainer');
  const grid = getEl('grid');

  function render() {
    renderMonitorGrid(grid, store.getFiltered());
    renderUrlPanel(getEl('urlPanelBody'), store.getAll());

    const { running, stopped, error } = store.counts();
    getEl('countRunning').textContent = running;
    getEl('countStopped').textContent = stopped;
    getEl('countError').textContent = error;
  }

  function showCommandModal(service, cmd) {
    getEl('modalTitle').textContent = `${cmd} — ${service}`;
    getEl('modalCmd').textContent = `$ ./monitor.sh ${cmd} ${service}`;
    openModal(CMD_MODAL_ID);
  }

  function cardAction(cmd, id) {
    const result = store.applyCardCommand(cmd, id);
    if (result.showCommand) {
      showCommandModal(id, cmd);
      return;
    }
    if (result.changed) {
      render();
      toast(`./monitor.sh ${cmd} ${id}`, cmd === 'stop' ? 'error' : 'success');
    }
  }

  function globalAction(cmd, target) {
    const result = store.applyGlobalCommand(cmd);
    if (result.showCommand) {
      showCommandModal(target, 'status');
      return;
    }
    if (result.changed) {
      render();
      toast(`./monitor.sh ${cmd} ${target}`, cmd === 'stop' ? 'error' : 'success');
    }
  }

  function filterCards(filter, btnEl) {
    store.setFilter(filter);
    document.querySelectorAll('.filter-btn').forEach((b) => b.classList.remove('active'));
    btnEl.classList.add('active');
    render();
  }

  // Header action bar (start/stop/restart/status all + urls toggle)
  delegate(document.querySelector('.header-actions'), {
    'global-cmd': (el) => globalAction(el.dataset.cmd, 'all'),
    'toggle-urls': () => getEl('urlPanel').classList.toggle('open'),
  });

  // Toolbar filters
  delegate(document.querySelector('.toolbar-left'), {
    filter: (el) => filterCards(el.dataset.filter, el),
  });

  // Service card actions (start/stop/restart/logs/status/enable/disable)
  delegate(grid, {
    'card-cmd': (el) => cardAction(el.dataset.cmd, el.dataset.id),
    'show-cmd': (el) => showCommandModal(el.dataset.id, el.dataset.cmd),
  });

  // URL panel close button
  delegate(document.querySelector('.url-panel-header'), {
    'close-url-panel': () => getEl('urlPanel').classList.toggle('open'),
  });

  // Modal close (backdrop click + close button)
  const modal = getEl(CMD_MODAL_ID);
  modal.addEventListener('click', (ev) => closeModalOnBackdropClick(ev, CMD_MODAL_ID));
  delegate(modal, {
    'close-modal': () => closeModal(CMD_MODAL_ID),
  });

  render();
}

initMonitorPage();
