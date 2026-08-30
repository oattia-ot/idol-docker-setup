/**
 * features/dashboard/state/dashboard-state.js
 * Business logic for the dashboard's service registry: holds service
 * state and the transitions allowed on it. Contains zero DOM code, so
 * it can be unit tested directly (e.g. with Jest/Vitest) without a browser.
 */

export const DASHBOARD_SERVICES = [
  { id: 'yacht',         name: 'yacht',         desc: 'Container Management UI',         port: 5001, status: 'stopped' },
  { id: 'dockge',        name: 'dockge',        desc: 'Docker Compose Stack Manager',     port: 5002, status: 'stopped' },
  { id: 'dozzle',        name: 'dozzle',        desc: 'Real-time Log Viewer',             port: 5003, status: 'running' },
  { id: 'cadvisor',      name: 'cadvisor',      desc: 'Container Metrics Collector',      port: 5004, status: 'running' },
  { id: 'prometheus',    name: 'prometheus',    desc: 'Metrics Collection & Storage',     port: 5005, status: 'running' },
  { id: 'grafana',       name: 'grafana',       desc: 'Metrics Visualization Dashboard',  port: 5006, status: 'running' },
  { id: 'loki',          name: 'loki',          desc: 'Log Aggregation System',           port: 5007, status: 'stopped' },
  { id: 'promtail',      name: 'promtail',      desc: 'Log Shipper for Loki',             port: 5008, status: 'stopped' },
  { id: 'dokemon',       name: 'dokemon',       desc: 'Simple Docker Monitor',            port: 5009, status: 'stopped' },
  { id: 'node-exporter', name: 'node-exporter', desc: 'System Metrics Exporter',          port: 5010, status: 'running' },
];

/**
 * Creates an isolated, mutable service store with the same transition
 * rules as the original main.js (start/stop/restart/logs/status), but
 * without touching the DOM. Returns plain data + pure mutators so the
 * UI layer stays a thin renderer.
 */
export function createDashboardStore(initialServices = DASHBOARD_SERVICES) {
  // Deep-ish copy so multiple store instances (e.g. in tests) don't share state
  let services = initialServices.map((s) => ({ ...s }));

  function getAll() {
    return services;
  }

  function findById(id) {
    return services.find((s) => s.id === id);
  }

  function counts() {
    return {
      running: services.filter((s) => s.status === 'running').length,
      stopped: services.filter((s) => s.status === 'stopped').length,
    };
  }

  /** Mirrors svcAction(cmd, id) from the original main.js. */
  function applyServiceCommand(cmd, id) {
    const service = findById(id);
    if (!service) return { changed: false };
    if (cmd === 'logs') return { changed: false, info: true };

    service.status = cmd === 'stop' ? 'stopped' : 'running';
    return { changed: true };
  }

  /** Mirrors globalAction(cmd) from the original main.js. */
  function applyGlobalCommand(cmd) {
    if (cmd === 'status') return { changed: false, info: true };
    services.forEach((s) => {
      s.status = cmd === 'stop' ? 'stopped' : 'running';
    });
    return { changed: true };
  }

  return { getAll, findById, counts, applyServiceCommand, applyGlobalCommand };
}
