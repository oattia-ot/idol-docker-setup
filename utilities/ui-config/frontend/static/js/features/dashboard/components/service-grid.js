/**
 * features/dashboard/components/service-grid.js
 * Pure presentation: turns a list of service records into markup.
 * No state, no fetch, no event wiring — just templating.
 */

function serviceCellTemplate(s) {
  return `
    <div class="svc-cell ${s.status}" id="cell-${s.id}">
      <div class="svc-name">${s.name}</div>
      <div class="svc-desc">${s.desc}</div>
      <div class="svc-meta">
        <span class="svc-port">:${s.port}</span>
        <span class="svc-status ${s.status}">
          <span class="sdot"></span>${s.status}
        </span>
      </div>
      <div class="svc-actions">
        <button class="svc-btn g" data-action="service-cmd" data-cmd="start" data-id="${s.id}">▶</button>
        <button class="svc-btn r" data-action="service-cmd" data-cmd="stop" data-id="${s.id}">■</button>
        <button class="svc-btn b" data-action="service-cmd" data-cmd="logs" data-id="${s.id}">≡ logs</button>
      </div>
      <a class="svc-url" href="http://localhost:${s.port}" target="_blank">localhost:${s.port}</a>
    </div>
  `;
}

/**
 * @param {HTMLElement} container
 * @param {Array} services
 */
export function renderServiceGrid(container, services) {
  if (!container) return;
  container.innerHTML = services.map(serviceCellTemplate).join('');
}
