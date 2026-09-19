/**
 * One-time CSS injection for the unified table/tree/badge styling.
 * Adds `.btn-root` (paired with the colorManager bug fix) alongside the
 * original ruleset, otherwise unchanged from the source script.
 */
export function injectContextListStyles() {
  const styleId = 'param-context-list-style';
  if (document.getElementById(styleId)) return;

  const style = document.createElement('style');
  style.id = styleId;
  style.textContent = `
    #paramContextsList .list-item,
    #paramContextsList .list-item *,
    .param-context-item,
    .list-item[style*="background: linear-gradient"] {
        background: transparent !important;
        background-color: transparent !important;
    }
    #paramContextsList .list-item {
        background: rgba(30, 41, 59, 0.5) !important;
        backdrop-filter: blur(2px);
        border-left: 5px solid #3b82f6;
        box-shadow: 0 2px 6px rgba(0,0,0,0.2);
    }
    #paramContextsList .list-item-title { color: #f1f5f9 !important; }
    #paramContextsList .list-item-subtitle { color: #94a3b8 !important; }
    #paramContextsList .action-buttons .btn {
        background: #1e293b !important;
        color: white !important;
        border: 1px solid #475569;
    }
    #paramContextsList .action-buttons .btn:hover { background: #334155 !important; }

    .data-table {
        width: 100%;
        border-collapse: collapse;
        background: #1e2937;
        border-radius: 8px;
        overflow: hidden;
        box-shadow: 0 2px 8px rgba(0,0,0,0.3);
    }
    .data-table th {
        background: #0f172a;
        color: #e2e8f0;
        font-weight: 600;
        text-transform: uppercase;
        font-size: 11px;
        letter-spacing: 0.05em;
        padding: 8px 6px;
        text-align: left;
    }
    .data-table td {
        padding: 8px 6px;
        border-top: 1px solid #334155;
        font-size: 13px;
    }
    .data-table tr:hover { background: rgba(59, 130, 246, 0.1); }
    .scroll-box {
        max-height: 420px;
        overflow-y: auto;
        border-radius: 8px;
        border: 1px solid #475569;
    }

    /* === Host Folder Hierarchy (Valid NiFi 2 Flows) === */
    .folder-tree-root { display: flex; flex-direction: column; gap: 10px; }
    .folder-tree-node {
        border: 1px solid #334155;
        border-radius: 8px;
        background: rgba(255,255,255,0.02);
        overflow: hidden;
    }
    .folder-tree-node > .folder-tree-children {
        padding: 8px 10px 10px 10px;
        border-top: 1px solid #334155;
        display: flex;
        flex-direction: column;
        gap: 8px;
    }
    .folder-summary {
        list-style: none;
        cursor: pointer;
        display: flex;
        align-items: center;
        gap: 8px;
        padding: 8px 10px;
        font-weight: 600;
        color: #e2e8f0;
        user-select: none;
    }
    .folder-summary::-webkit-details-marker { display: none; }
    .folder-summary .fa-folder { color: #60a5fa; transition: transform .15s ease; }
    .folder-tree-node[open] > .folder-summary .fa-folder { color: #facc15; }
    .folder-name { flex: 0 0 auto; color: #e2e8f0; }
    .folder-count {
        margin-left: auto;
        font-size: 11px;
        font-weight: 500;
        color: #94a3b8;
        background: rgba(148,163,184,0.12);
        padding: 2px 8px;
        border-radius: 9999px;
    }
    .core-badge, .user-badge, .tutorial-badge, .based-badge, .folder-badge, .root-badge {
        display: inline-block;
        font-size: 10px;
        font-weight: 700;
        text-transform: uppercase;
        letter-spacing: 0.04em;
        padding: 2px 8px;
        border-radius: 9999px;
        margin-right: 6px;
    }
    .core-badge     { background: rgba(59,130,246,0.18);  color: #60a5fa !important; }
    .user-badge     { background: rgba(245,158,11,0.18);  color: #f59e0b !important; }
    .tutorial-badge { background: rgba(168,85,247,0.18);  color: #c084fc !important; }
    .based-badge    { background: rgba(20,184,166,0.18);  color: #14b8a6 !important; }
    .folder-badge   { background: rgba(100,116,139,0.18); color: #94a3b8 !important; }
    .root-badge     { background: rgba(16,185,129,0.18);  color: #34d399 !important; }

    .btn-feature, .btn-user-flow, .btn-tutorial, .btn-folder, .btn-root, .btn-based {
        background: #1e293b !important;
        color: #e2e8f0 !important;
        border: 1px solid #475569 !important;
    }
    .btn-feature:hover, .btn-user-flow:hover, .btn-tutorial:hover,
    .btn-folder:hover, .btn-root:hover, .btn-based:hover { background: #334155 !important; }

    /* FIX: dedicated accent border so Root buttons no longer read as Core */
    .btn-root { border-color: rgba(16,185,129,0.45) !important; }

    /* Based NiFi button accent */
    .btn-based { border-color: rgba(20,184,166,0.45) !important; }
    
    tr.selected-row, tr.selected-row-user, tr.selected-row-folder {
        background: rgba(16,185,129,0.08) !important;
    }
  `;
  document.head.appendChild(style);
  console.log('[CSS] Unified styling applied');
}
