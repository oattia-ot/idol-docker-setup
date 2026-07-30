/**
 * idol-versions.js
 * Fetches idol-versions.json and populates version <select> dropdowns.
 *
 * Handles:
 *   #basic-idol-version   — all versions, selects latest:true
 *   #data-admin-version   — all versions, selects newest dataAdminStable:true
 *   #rich-media-version   — all versions, selects newest richMediaStable:true
 */

(function () {
  const INFO_ID = "idol-version-info"; // optional detail panel (basic select only)

  // Resolve idol-versions.json relative to THIS script file,
  // not relative to the HTML page that loads it.
  const _scriptSrc = (document.currentScript || {}).src || "";
  const JSON_PATH  = _scriptSrc.replace(/\/[^/]+$/, "/") + "idol-versions.json";

  // ── Helpers ────────────────────────────────────────────────────────────────

  function formatDate(isoString) {
    return new Date(isoString).toLocaleDateString(undefined, {
      year: "numeric", month: "long", day: "numeric",
    });
  }

  function renderInfoPanel(version) {
    const panel = document.getElementById(INFO_ID);
    if (!panel) return;
    panel.innerHTML = `
      <strong>Version ${version.value}</strong>
      &nbsp;·&nbsp;
      <span>Released: ${formatDate(version.releaseDate)}</span>
      <p style="margin: 6px 0 0;">${version.description}</p>
    `;
  }

  /**
   * Populate a <select> from the versions array.
   *
   * @param {string}   selectId   - The id of the <select> element
   * @param {Array}    versions   - Full versions array from JSON
   * @param {Function} pickDefault - (versions) => version object to pre-select
   * @param {Function} [onChange] - optional callback(chosenVersion) on change
   */
  function populateSelect(selectId, versions, pickDefault, onChange) {
    const select = document.getElementById(selectId);
    if (!select) return; // element not on this page — skip silently

    select.innerHTML = "";

    const defaultVersion = pickDefault(versions) || versions[0];

    versions.forEach((v) => {
      const option = document.createElement("option");
      option.value = v.value;
      option.dataset.releaseDate = v.releaseDate;
      option.dataset.description = v.description;

      // Append "(stable)" label for stable versions in non-basic selects
      const isDefault = v.value === defaultVersion.value;
      option.textContent = isDefault && selectId !== "basic-idol-version"
        ? `${v.value}`
        : v.label;

      if (isDefault) option.selected = true;
      select.appendChild(option);
    });

    if (onChange) {
      select.addEventListener("change", () => {
        const chosen = versions.find((v) => v.value === select.value);
        if (chosen) onChange(chosen);
      });
    }
  }

  // ── Init ───────────────────────────────────────────────────────────────────

  function init() {
    fetch(JSON_PATH)
      .then((res) => {
        if (!res.ok) throw new Error(`HTTP ${res.status} – could not load ${JSON_PATH}`);
        return res.json();
      })
      .then(({ versions }) => {

        // 1. Basic IDOL version — selects latest:true
        populateSelect(
          "basic-idol-version",
          versions,
          (vs) => vs.find((v) => v.latest),
          (chosen) => renderInfoPanel(chosen)
        );
        // also render the initial info panel
        const initialBasic = versions.find((v) => v.latest) || versions[0];
        if (initialBasic) renderInfoPanel(initialBasic);

        // 2. Data Admin — selects newest version where dataAdminStable:true
        populateSelect(
          "data-admin-version",
          versions,
          (vs) => vs.find((v) => v.dataAdminStable)
        );

        // 3. Rich Media — selects newest version where richMediaStable:true
        populateSelect(
          "rich-media-version",
          versions,
          (vs) => vs.find((v) => v.richMediaStable)
        );

      })
      .catch((err) => console.error("[idol-versions] Failed to load versions:", err));
  }

  if (document.readyState === "loading") {
    document.addEventListener("DOMContentLoaded", init);
  } else {
    init();
  }
})();