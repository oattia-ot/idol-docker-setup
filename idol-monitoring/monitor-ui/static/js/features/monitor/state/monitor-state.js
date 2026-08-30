/**
 * Simple reactive state store for the monitor
 */

let state = {
  services: [],
  filter: 'all',        // 'all' | 'healthy' | 'degraded'
  activeTab: 'idol-demo', // 'idol-demo' | 'monitoring'   ← default tab
  selectedId: null,
  lastUpdated: null
};

const listeners = new Set();

function notify() {
  const snapshot = getState();
  listeners.forEach(fn => {
    try { fn(snapshot); } catch (e) { console.error(e); }
  });
}

export function getState() {
  return {
    services: [...state.services],
    filter: state.filter,
    activeTab: state.activeTab,
    selectedId: state.selectedId,
    lastUpdated: state.lastUpdated
  };
}

export function setServices(services) {
  state.services = Array.isArray(services) ? services : [];
  state.lastUpdated = new Date().toISOString();
  notify();
}

export function setFilter(filter) {
  if (['all', 'healthy', 'degraded'].includes(filter)) {
    state.filter = filter;
    notify();
  }
}

export function setActiveTab(tab) {
  if (['idol-demo', 'monitoring'].includes(tab)) {
    state.activeTab = tab;
    notify();
  }
}

export function setSelected(id) {
  state.selectedId = id || null;
  notify();
}

export function subscribe(listener) {
  listeners.add(listener);
  // Immediately call with current state
  listener(getState());
  return () => listeners.delete(listener);
}

export function getFilteredServices() {
  const { services, filter, activeTab } = state;
  
  let result = services;

  // Filter by tab first
  if (activeTab === 'idol-demo') {
    result = result.filter(s => s.group === 'idol-demo');
  } else if (activeTab === 'monitoring') {
    result = result.filter(s => s.group === 'monitoring');
  }

  // Then apply status filter
  if (filter !== 'all') {
    result = result.filter(s => s.status === filter);
  }

  return result;
}

export function getSelectedService() {
  if (!state.selectedId) return null;
  return state.services.find(s => s.id === state.selectedId) || null;
}
