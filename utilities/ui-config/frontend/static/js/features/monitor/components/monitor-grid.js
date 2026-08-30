/**
 * features/monitor/components/monitor-grid.js
 * Pure presentation for the monitor service cards + URL side panel.
 */

const HOST = 'localhost';

function cardTemplate(s) {
  return `
    <div class="card ${s.status}" id="card-${s.id}">
      <div class="card-header">
        <div>
          <div class="card-name">${s.name}</div>
          <div class="card-desc">${s.desc}</div>
        </div>
        <div class="card-badges">
          <span class="port-badge">:${s.port}</span>
          <span class="status-badge ${s.status}">
            <span class="status-dot ${s.status === 'running' ? 'pulse' : ''}"></span>
            ${s.status}
          </span>
        </div>
      </div>
      <div class="card-divider"></div>
      <div class="url-row">
        <span class="url-icon">⤷</span>
        <a class="url-link" href="http://${HOST}:${s.port}" target="_blank">http://${HOST}:${s.port}</a>
      </div>
      <div class="card-actions">
        <button class="btn btn-green" data-action="card-cmd" data-cmd="start" data-id="${s.id}">▶ start</button>
        <button class="btn btn-red" data-action="card-cmd" data-cmd="stop" data-id="${s.id}">■ stop</button>
        <button class="btn btn-amber" data-action="card-cmd" data-cmd="restart" data-id="${s.id}">↺ restart</button>
        <button class="btn btn-accent" data-action="card-cmd" data-cmd="logs" data-id="${s.id}">≡ logs</button>
        <button class="btn" data-action="card-cmd" data-cmd="status" data-id="${s.id}">◉ status</button>
        <button class="btn" data-action="show-cmd" data-cmd="enable" data-id="${s.id}">+ enable</button>
        <button class="btn btn-red" data-action="show-cmd" data-cmd="disable" data-id="${s.id}" style="opacity:0.7">− disable</button>
      </div>
    </div>
  `;
}

export function renderMonitorGrid(container, services) {
  if (!container) return;
  container.innerHTML = services.map(cardTemplate).join('');
}

export function renderUrlPanel(container, services) {
  if (!container) return;
  container.innerHTML = services
    .map(
      (s) => `
    <div class="url-panel-item">
      <span class="url-panel-name">${s.name}</span>
      <a class="url-panel-href" href="http://${HOST}:${s.port}" target="_blank">http://${HOST}:${s.port}</a>
    </div>
  `
    )
    .join('');
}
