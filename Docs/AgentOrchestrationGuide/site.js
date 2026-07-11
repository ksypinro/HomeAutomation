(function () {
  "use strict";

  const currentFile = window.location.pathname.split("/").pop() || "index.html";
  document.querySelectorAll(".site-nav a").forEach((link) => {
    if (link.getAttribute("href") === currentFile) {
      link.setAttribute("aria-current", "page");
    }
  });

  const menuButton = document.querySelector(".menu-button");
  if (menuButton) {
    menuButton.addEventListener("click", () => {
      const isOpen = document.body.classList.toggle("nav-open");
      menuButton.setAttribute("aria-expanded", String(isOpen));
    });
  }

  document.querySelectorAll(".site-nav a").forEach((link) => {
    link.addEventListener("click", () => document.body.classList.remove("nav-open"));
  });

  const catalogRoot = document.querySelector("[data-catalog-groups]");
  if (catalogRoot && Array.isArray(window.AGENT_CATALOG)) {
    renderCatalog(catalogRoot);
  }

  function renderCatalog(root) {
    const requestedGroups = root.dataset.catalogGroups
      .split(",")
      .map((value) => value.trim())
      .filter(Boolean);
    const agents = window.AGENT_CATALOG.filter((agent) => requestedGroups.includes(agent.group));
    const host = root.querySelector("#agent-catalog");
    if (!host) return;

    requestedGroups.forEach((group) => {
      const groupAgents = agents.filter((agent) => agent.group === group);
      if (!groupAgents.length) return;

      const section = document.createElement("section");
      section.className = "agent-group";
      section.dataset.group = group;
      section.innerHTML = `
        <div class="agent-group-header">
          <h2>${escapeHTML(group)}</h2>
          <span>${groupAgents.length}</span>
        </div>
        <div class="agent-grid"></div>
      `;
      const grid = section.querySelector(".agent-grid");
      groupAgents.forEach((agent) => grid.appendChild(agentCard(agent)));
      host.appendChild(section);
    });

    const visibleCount = root.querySelector("#visible-count");
    if (visibleCount) visibleCount.textContent = `${agents.length} agents`;
    wireSearch(root, agents.length);
  }

  function agentCard(agent) {
    const article = document.createElement("article");
    article.className = "agent-card";
    article.id = agent.slug;
    article.dataset.runtime = agent.runtime;
    article.dataset.search = [
      agent.name,
      agent.id,
      agent.group,
      agent.purpose,
      agent.runs,
      agent.input,
      agent.process,
      agent.calls,
      agent.output,
      agent.failure
    ].join(" ").toLowerCase();

    const sourceLabel = agent.source.split("/").pop();
    article.innerHTML = `
      <div class="agent-topline">
        <div>
          <h3>${escapeHTML(agent.name)}</h3>
          <span class="agent-id">${escapeHTML(agent.id)}</span>
        </div>
        <span class="runtime-tag">${escapeHTML(runtimeLabel(agent.runtime))}</span>
      </div>
      <p class="agent-purpose">${escapeHTML(agent.purpose)}</p>
      <dl class="agent-facts">
        <dt>Runs</dt><dd>${escapeHTML(agent.runs)}</dd>
        <dt>Receives</dt><dd>${escapeHTML(agent.input)}</dd>
        <dt>Process</dt><dd>${escapeHTML(agent.process)}</dd>
        <dt>Calls</dt><dd>${escapeHTML(agent.calls)}</dd>
        <dt>Emits</dt><dd>${escapeHTML(agent.output)}</dd>
        <dt>Failure</dt><dd>${escapeHTML(agent.failure)}</dd>
      </dl>
      <a class="source-link" href="${encodeURI(agent.source)}" title="Open ${escapeHTML(agent.source)}">${escapeHTML(sourceLabel)}:${agent.line}</a>
    `;
    return article;
  }

  function runtimeLabel(runtime) {
    const labels = {
      registry: "graph registry",
      embedded: "embedded",
      loop: "loop worker"
    };
    return labels[runtime] || runtime;
  }

  function wireSearch(root, total) {
    const input = root.querySelector("#agent-search");
    const count = root.querySelector("#visible-count");
    if (!input) return;

    input.addEventListener("input", () => {
      const query = input.value.trim().toLowerCase();
      let visible = 0;
      root.querySelectorAll(".agent-card").forEach((card) => {
        const matches = !query || card.dataset.search.includes(query);
        card.classList.toggle("is-hidden", !matches);
        if (matches) visible += 1;
      });
      root.querySelectorAll(".agent-group").forEach((group) => {
        const hasVisible = Boolean(group.querySelector(".agent-card:not(.is-hidden)"));
        group.classList.toggle("is-hidden", !hasVisible);
      });
      if (count) count.textContent = query ? `${visible} of ${total}` : `${total} agents`;
    });
  }

  function escapeHTML(value) {
    return String(value)
      .replaceAll("&", "&amp;")
      .replaceAll("<", "&lt;")
      .replaceAll(">", "&gt;")
      .replaceAll('"', "&quot;")
      .replaceAll("'", "&#039;");
  }
})();
