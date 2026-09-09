/**
 * features/monitor/state/monitor-state.js
 * Pure business logic for the monitor page: service registry, the
 * current filter, and the status transitions triggered by actions.
 * Mirrors the SERVICES array + cardAction/globalAction/filterCards
 * logic from the original monitor-config.js, with no DOM access.
 */

export const MONITOR_SERVICES = [
  { id: 'yacht',         name: 'yacht',         desc: 'Container Management UI',         port: 5001, status: 'stopped', group: 'ui' },
  { id: 'dockge',        name: 'dockge',        desc: 'Docker Compose Stack Manager',     port: 5002, status: 'stopped', group: 'ui' },
  { id: 'dozzle',        name: 'dozzle',        desc: 'Real-time Log Viewer',             port: 5003, status: 'running', group: 'logging' },
  { id: 'cadvisor',      name: 'cadvisor',      desc: 'Container Metrics Collector',      port: 5004, status: 'running', group: 'metrics' },
  { id: 'prometheus',    name: 'prometheus',    desc: 'Metrics Collection & Storage',     port: 5005, status: 'running', group: 'metrics' },
  { id: 'grafana',       name: 'grafana',       desc: 'Metrics Visualization Dashboard',  port: 5006, status: 'running', group: 'metrics' },
  { id: 'loki',          name: 'loki',          desc: 'Log Aggregation System',           port: 5007, status: 'stopped', group: 'logging' },
  { id: 'promtail',      name: 'promtail',      desc: 'Log Shipper for Loki',             port: 5008, status: 'stopped', group: 'logging' },
  { id: 'dokemon',       name: 'dokemon',       desc: 'Simple Docker Monitor',            port: 5009, status: 'stopped', group: 'ui' },
  { id: 'node-exporter', name: 'node-exporter', desc: 'System Metrics Exporter',          port: 5010, status: 'running', group: 'metrics' },
];

export function createMonitorStore(initialServices = MONITOR_SERVICES) {
  let services = initialServices.map((s) => ({ ...s }));
  let currentFilter = 'all';

  function getAll() {
    return services;
  }

  function getFiltered() {
    return currentFilter === 'all' ? services : services.filter((s) => s.status === currentFilter);
  }

  function setFilter(filter) {
    currentFilter = filter;
  }

  function getFilter() {
    return currentFilter;
  }

  function findById(id) {
    return services.find((s) => s.id === id);
  }

  function counts() {
    return {
      running: services.filter((s) => s.status === 'running').length,
      stopped: services.filter((s) => s.status === 'stopped').length,
      error: services.filter((s) => s.status === 'error').length,
    };
  }

  /** Mirrors cardAction(cmd, service). 'logs'/'status' are informational only. */
  function applyCardCommand(cmd, id) {
    if (cmd === 'logs' || cmd === 'status') return { changed: false, showCommand: true };
    const service = findById(id);
    if (!service) return { changed: false };

    if (cmd === 'start') service.status = 'running';
    if (cmd === 'stop') service.status = 'stopped';
    if (cmd === 'restart') service.status = 'running';
    return { changed: true };
  }

  /** Mirrors globalAction(cmd, target). */
  function applyGlobalCommand(cmd) {
    if (cmd === 'status') return { changed: false, showCommand: true };
    services.forEach((s) => {
      if (cmd === 'start') s.status = 'running';
      if (cmd === 'stop') s.status = 'stopped';
      if (cmd === 'restart') s.status = 'running';
    });
    return { changed: true };
  }

  return {
    getAll,
    getFiltered,
    setFilter,
    getFilter,
    findById,
    counts,
    applyCardCommand,
    applyGlobalCommand,
  };
}
