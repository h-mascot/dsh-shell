(() => {
  "use strict";

  if (window.__DSH_EFFORT_CONTROL__ && typeof window.__DSH_EFFORT_CONTROL__.destroy === "function") {
    window.__DSH_EFFORT_CONTROL__.destroy();
  }

  const LEVELS = ["Off", "High", "Max"];
  const FOUNDER_IMAGES = {
    Off: "__DSH_FOUNDER_OFF_DATA_URI__",
    High: "__DSH_FOUNDER_HIGH_DATA_URI__",
    Max: "__DSH_FOUNDER_MAX_DATA_URI__",
  };
  // Baked in at script-build time from UserDefaults "founderThemeEnabled";
  // updated live via window.__DSH_EFFORT_CONTROL__.setFounderTheme(enabled).
  let founderEnabled = __DSH_FOUNDER_THEME_ENABLED__;
  const STYLE_ID = "dsh-effort-control-style";
  const SLOT_SELECTOR = '[data-slot="conversation.input.right"]';
  const MODEL_SELECTOR = 'button[aria-label^="Select model"]';
  const HERO_SELECTORS = [
    '[data-dsh-view="new-session"]',
    '[data-page="new-session"]',
    '[data-view="new-session"]',
    '[data-testid="new-session"]',
  ];

  let rail = null;
  let input = null;
  let tooltip = null;
  let mountedSlot = null;
  let mountedTrigger = null;
  let hero = null;
  let founderLayers = [];
  let visibleFounderLayer = 0;
  let renderedFounderLevel = null;
  let founderRenderToken = 0;
  let themeSnapshot = null;
  let observer = null;
  let reconcileTimer = null;
  let interval = null;
  let applying = false;
  let applyTimer = null;
  let desiredLevel = null;
  let confirmedLevel = null;
  let level = null;
  let unavailable = false;
  let tooltipTimer = null;

  function normalize(value) {
    return String(value || "").replace(/\s+/g, " ").trim();
  }

  function isVisible(element) {
    if (!element || !element.isConnected) return false;
    const style = window.getComputedStyle(element);
    return style.display !== "none" && style.visibility !== "hidden" && element.getClientRects().length > 0;
  }

  function levelFromLabel(value) {
    const match = normalize(value).match(/reasoning\s+effort\s+(Off|High|Max)\b/i);
    return match ? LEVELS.find((levelName) => levelName.toLowerCase() === match[1].toLowerCase()) : null;
  }

  function modelTrigger() {
    // Live DSH renders the model button in the SIBLING conversation.input.model slot,
    // not inside conversation.input.right. Search the composer neighborhood: the right
    // slot itself, its siblings, then the shared trailing row / composer bar container.
    const slots = document.querySelectorAll(SLOT_SELECTOR);
    for (const slot of slots) {
      const inSlot = slot.querySelector(MODEL_SELECTOR);
      if (inSlot) return inSlot;
      const parent = slot.parentElement;
      if (parent) {
        const inParent = parent.querySelector(MODEL_SELECTOR);
        if (inParent) return inParent;
      }
    }
    const composer = document.querySelector('[data-slot="conversation.composer.bar"], [data-slot="conversation.composer"]');
    return composer ? composer.querySelector(MODEL_SELECTOR) : null;
  }

  function readNativeLevel(trigger) {
    if (!trigger) return null;
    return levelFromLabel(trigger.getAttribute("aria-label")) || levelFromLabel(trigger.getAttribute("title"));
  }

  function activeConversationPresent() {
    return Boolean(document.querySelector(
      '[data-conversation-id], [data-message-id], [data-testid*="message" i], [role="log"]'
    ));
  }

  function findHeroTarget(slot) {
    // P2 fix: a stale/hidden new-session marker can persist in the DOM during an
    // active conversation. Only accept a hero target when no conversation is
    // active, and explicit markers must additionally be visible.
    if (activeConversationPresent()) return null;

    const explicit = document.querySelector(HERO_SELECTORS.join(","));
    if (explicit && isVisible(explicit)) return explicit;

    const pathname = window.location.pathname || "/";
    const looksLikeNewSession = pathname === "/" || pathname === "/new" || /new-session/i.test(pathname);
    if (looksLikeNewSession) {
      // Live DSH has no <main> around the composer; the stage that holds the
      // hero heading + composer is .wSkVaW_composerSeat. Keep main/role=main
      // first for the fixture and future DSH versions that add landmarks.
      return slot.closest('main, [role="main"], .wSkVaW_composerSeat') || slot.parentElement;
    }
    return null;
  }

  function installStyle() {
    if (document.getElementById(STYLE_ID)) return;
    const style = document.createElement("style");
    style.id = STYLE_ID;
    style.textContent = `
      .dsh-effort-control {
        --dsh-effort-accent: #536dfe;
        --dsh-effort-muted: color-mix(in srgb, currentColor 36%, transparent);
        position: relative;
        display: inline-flex;
        flex: 0 1 180px;
        width: clamp(152px, 22vw, 180px);
        min-width: 152px;
        height: 28px;
        align-items: center;
        margin-inline: 5px;
        color: currentColor;
        vertical-align: middle;
        isolation: isolate;
      }
      .dsh-effort-control.is-max { --dsh-effort-accent: #c69b3c; }
      .dsh-effort-control.is-unavailable { --dsh-effort-accent: #8f8f8f; }
      .dsh-effort-control .dsh-effort-line {
        position: absolute;
        inset-inline: 8px;
        top: 50%;
        height: 2px;
        border-radius: 999px;
        background: color-mix(in srgb, currentColor 21%, transparent);
        transform: translateY(-50%);
      }
      .dsh-effort-control .dsh-effort-line::after {
        content: "";
        position: absolute;
        inset: 0;
        border-radius: inherit;
        background: var(--dsh-effort-accent);
        transform-origin: left center;
        transform: scaleX(var(--dsh-effort-progress, 0));
        opacity: .72;
      }
      .dsh-effort-control .dsh-effort-ticks {
        position: absolute;
        inset-inline: 8px;
        top: 50%;
        height: 10px;
        transform: translateY(-50%);
        pointer-events: none;
      }
      .dsh-effort-control .dsh-effort-tick {
        position: absolute;
        top: 50%;
        width: 5px;
        height: 5px;
        border: 1px solid color-mix(in srgb, currentColor 54%, transparent);
        border-radius: 50%;
        background: Canvas;
        transform: translate(-50%, -50%);
      }
      .dsh-effort-control .dsh-effort-tick:nth-child(1) { left: 0; }
      .dsh-effort-control .dsh-effort-tick:nth-child(2) { left: 50%; }
      .dsh-effort-control .dsh-effort-tick:nth-child(3) { left: 100%; }
      .dsh-effort-control .dsh-effort-thumb {
        position: absolute;
        top: 50%;
        left: var(--dsh-effort-thumb, 0%);
        width: 13px;
        height: 13px;
        border: 2px solid var(--dsh-effort-accent);
        border-radius: 50%;
        background: Canvas;
        box-shadow: 0 0 0 2px color-mix(in srgb, var(--dsh-effort-accent) 16%, transparent);
        transform: translate(-50%, -50%);
        pointer-events: none;
        transition: left 160ms ease, border-color 160ms ease, box-shadow 160ms ease;
      }
      .dsh-effort-control input[type="range"] {
        position: absolute;
        inset: 0;
        width: 100%;
        height: 100%;
        margin: 0;
        cursor: ew-resize;
        opacity: 0;
      }
      .dsh-effort-control input[type="range"]:focus-visible + .dsh-effort-line {
        box-shadow: 0 0 0 3px color-mix(in srgb, var(--dsh-effort-accent) 28%, transparent);
      }
      .dsh-effort-control input[type="range"]:disabled { cursor: not-allowed; }
      .dsh-effort-control .dsh-effort-tooltip {
        position: absolute;
        left: 50%;
        bottom: calc(100% + 7px);
        z-index: 4;
        padding: 4px 7px;
        border: 1px solid color-mix(in srgb, currentColor 18%, transparent);
        border-radius: 5px;
        background: Canvas;
        color: CanvasText;
        box-shadow: 0 3px 14px color-mix(in srgb, #000 18%, transparent);
        font: 11px/1.2 system-ui, sans-serif;
        white-space: nowrap;
        opacity: 0;
        pointer-events: none;
        transform: translate(-50%, 3px);
        transition: opacity 140ms ease, transform 140ms ease;
      }
      .dsh-effort-control.is-tooltip-visible .dsh-effort-tooltip,
      .dsh-effort-control:hover .dsh-effort-tooltip,
      .dsh-effort-control:focus-within .dsh-effort-tooltip {
        opacity: 1;
        transform: translate(-50%, 0);
      }
      .dsh-effort-hero-host { position: relative; isolation: isolate; }
      .dsh-effort-hero-host > .dsh-effort-founder-layer {
        position: absolute;
        inset: 0;
        z-index: 0;
        pointer-events: none;
        background-position: center;
        background-repeat: no-repeat;
        background-size: cover;
        opacity: 0;
        transition: opacity 620ms ease;
      }
      /* The live hero is wide and shallow. Source portraits put the face high
         (eyes ~19-20% from top for Off/High, ~31% for Max), so vertical
         centering crops it. Anchor Off/High to the top edge and keep Max
         centered (its source is wider, so centering already shows the face). */
      .dsh-effort-hero-host > .dsh-effort-founder-layer[data-dsh-level="Off"],
      .dsh-effort-hero-host > .dsh-effort-founder-layer[data-dsh-level="High"] {
        background-position: center 14%;
      }
      .dsh-effort-hero-host > .dsh-effort-founder-layer[data-dsh-level="Max"] {
        background-position: center 31%;
      }
      .dsh-effort-hero-host > :not(.dsh-effort-founder-layer) {
        position: relative;
        z-index: 1;
      }
      .dsh-effort-max-composer { box-shadow: inset 0 -1px 0 #c69b3c; }
      .dsh-effort-max-send { box-shadow: 0 0 0 1px color-mix(in srgb, #c69b3c 66%, transparent); }
      @media (prefers-reduced-motion: reduce) {
        .dsh-effort-control .dsh-effort-thumb,
        .dsh-effort-control .dsh-effort-tooltip,
        .dsh-effort-hero-host > .dsh-effort-founder-layer { transition: none; }
      }
      @media (max-width: 520px) {
        .dsh-effort-control { width: 152px; min-width: 144px; margin-inline: 3px; }
      }
    `;
    document.head.appendChild(style);
  }

  function showTooltip() {
    if (!rail) return;
    rail.classList.add("is-tooltip-visible");
    window.clearTimeout(tooltipTimer);
    tooltipTimer = window.setTimeout(() => {
      if (document.activeElement !== input && !rail.matches(":hover")) {
        rail.classList.remove("is-tooltip-visible");
      }
    }, 1800);
  }

  function snapshotThemeNode(node) {
    if (!node) return null;
    return {
      node,
      dark: node.classList.contains("dark"),
      light: node.classList.contains("light"),
      dataTheme: node.getAttribute("data-theme"),
      dataColorScheme: node.getAttribute("data-color-scheme"),
      colorScheme: node.style.colorScheme,
    };
  }

  function snapshotTheme() {
    themeSnapshot = [snapshotThemeNode(document.documentElement), snapshotThemeNode(document.body)];
  }

  function forceTheme(dark) {
    if (!themeSnapshot) snapshotTheme();
    for (const node of [document.documentElement, document.body]) {
      if (!node) continue;
      node.classList.toggle("dark", dark);
      node.classList.toggle("light", !dark);
      if (node.hasAttribute("data-theme")) node.setAttribute("data-theme", dark ? "dark" : "light");
      if (node.hasAttribute("data-color-scheme")) node.setAttribute("data-color-scheme", dark ? "dark" : "light");
      node.style.colorScheme = dark ? "dark" : "light";
    }
  }

  function restoreTheme() {
    if (!themeSnapshot) return;
    for (const saved of themeSnapshot) {
      if (!saved || !saved.node.isConnected) continue;
      saved.node.classList.toggle("dark", saved.dark);
      saved.node.classList.toggle("light", saved.light);
      if (saved.dataTheme === null) saved.node.removeAttribute("data-theme");
      else saved.node.setAttribute("data-theme", saved.dataTheme);
      if (saved.dataColorScheme === null) saved.node.removeAttribute("data-color-scheme");
      else saved.node.setAttribute("data-color-scheme", saved.dataColorScheme);
      saved.node.style.colorScheme = saved.colorScheme;
    }
    themeSnapshot = null;
  }

  function updateTooltip() {
    if (!tooltip) return;
    const label = unavailable || level === null ? "Unavailable" : LEVELS[level];
    tooltip.textContent = `Reasoning · ${label}`;
    if (input) {
      input.setAttribute("aria-valuetext", label);
      input.title = `Reasoning · ${label}`;
    }
  }

  function renderRail() {
    if (!rail || !input) return;
    const progress = level === null ? 0 : level / (LEVELS.length - 1);
    const label = unavailable || level === null ? "Unavailable" : LEVELS[level];
    rail.classList.toggle("is-max", label === "Max");
    rail.classList.toggle("is-unavailable", unavailable || level === null);
    rail.style.setProperty("--dsh-effort-progress", String(progress));
    rail.style.setProperty("--dsh-effort-thumb", `${progress * 100}%`);
    input.value = String(level === null ? 0 : level);
    input.disabled = level === null;
    input.setAttribute("aria-valuetext", label);
    input.title = `Reasoning · ${label}`;
    updateTooltip();
  }

  function createRail() {
    const control = document.createElement("div");
    control.className = "dsh-effort-control";
    control.setAttribute("data-dsh-effort-control", "true");
    control.innerHTML = `
      <input type="range" min="0" max="2" step="1" value="0" aria-label="Reasoning effort" aria-valuetext="Unavailable">
      <span class="dsh-effort-line" aria-hidden="true"></span>
      <span class="dsh-effort-ticks" aria-hidden="true"><i class="dsh-effort-tick"></i><i class="dsh-effort-tick"></i><i class="dsh-effort-tick"></i></span>
      <span class="dsh-effort-thumb" aria-hidden="true"></span>
      <span class="dsh-effort-tooltip" role="tooltip"></span>
    `;
    rail = control;
    input = control.querySelector('input[type="range"]');
    tooltip = control.querySelector('[role="tooltip"]');
    input.setAttribute("aria-describedby", `${STYLE_ID}-tooltip`);
    tooltip.id = `${STYLE_ID}-tooltip`;
    input.addEventListener("focus", showTooltip);
    input.addEventListener("pointerdown", showTooltip);
    input.addEventListener("input", () => {
      level = Number(input.value);
      unavailable = false;
      showTooltip();
      renderRail();
      scheduleApply();
    });
    input.addEventListener("change", () => {
      showTooltip();
      scheduleApply();
    });
    return control;
  }

  function updateAccent() {
    if (mountedSlot) {
      mountedSlot.classList.toggle("dsh-effort-max-composer", level === 2 && !unavailable);
      const sendButton = Array.from(mountedSlot.querySelectorAll("button")).find((button) => /send/i.test(button.getAttribute("aria-label") || ""));
      if (sendButton) sendButton.classList.toggle("dsh-effort-max-send", level === 2 && !unavailable);
    }
  }

  function mountRail(slot, trigger) {
    if (!rail) createRail();
    if (rail.parentElement !== slot || rail.nextElementSibling !== trigger) {
      rail.remove();
      trigger.before(rail);
    }
    mountedSlot = slot;
    mountedTrigger = trigger;
    renderRail();
    updateAccent();
  }

  function detachRail() {
    if (rail) rail.remove();
    if (mountedSlot) {
      mountedSlot.classList.remove("dsh-effort-max-composer");
      Array.from(mountedSlot.querySelectorAll(".dsh-effort-max-send")).forEach((button) => button.classList.remove("dsh-effort-max-send"));
    }
    mountedSlot = null;
    mountedTrigger = null;
  }

  function addFounderTreatment(target) {
    if (hero === target) return;
    removeFounderTreatment();
    hero = target;
    if (!hero) return;
    snapshotTheme();
    hero.classList.add("dsh-effort-hero-host");
    hero.setAttribute("data-dsh-effort-hero", "true");
    founderLayers = [0, 1].map(() => {
      const layer = document.createElement("div");
      layer.className = "dsh-effort-founder-layer";
      layer.setAttribute("aria-hidden", "true");
      hero.insertBefore(layer, hero.firstChild);
      return layer;
    });
    if (level !== null && !unavailable) {
      founderLayers[0].style.backgroundImage = `url("${FOUNDER_IMAGES[LEVELS[level]]}")`;
      founderLayers[0].setAttribute("data-dsh-level", LEVELS[level]);
    }
    founderLayers[0].style.opacity = "1";
    founderLayers[1].style.opacity = "0";
    visibleFounderLayer = 0;
    renderedFounderLevel = null;
  }

  function removeFounderTreatment() {
    if (!hero) return;
    founderLayers.forEach((layer) => layer.remove());
    hero.classList.remove("dsh-effort-hero-host");
    hero.removeAttribute("data-dsh-effort-hero");
    founderLayers = [];
    renderedFounderLevel = null;
    hero = null;
    restoreTheme();
  }

  function renderFounder() {
    if (!hero || !founderLayers.length) return;
    if (unavailable || level === null) {
      founderRenderToken += 1;
      founderLayers.forEach((layer) => { layer.style.opacity = "0"; });
      restoreTheme();
      renderedFounderLevel = null;
      return;
    }
    if (renderedFounderLevel === level) return;
    const image = FOUNDER_IMAGES[LEVELS[level]];
    if (!image || image.indexOf("__DSH_") === 0) return;
    forceTheme(level === 2);
    const next = visibleFounderLayer === 0 ? 1 : 0;
    const renderToken = ++founderRenderToken;
    founderLayers[next].style.backgroundImage = `url("${image}")`;
    founderLayers[next].setAttribute("data-dsh-level", LEVELS[level]);
    renderedFounderLevel = level;
    window.requestAnimationFrame(() => {
      if (!hero || !founderLayers.length || renderToken !== founderRenderToken) return;
      founderLayers[next].style.opacity = "1";
      founderLayers[visibleFounderLayer].style.opacity = "0";
      visibleFounderLayer = next;
    });
  }

  function updateHero(slot) {
    const target = founderEnabled ? findHeroTarget(slot) : null;
    if (!target) {
      removeFounderTreatment();
      return;
    }
    addFounderTreatment(target);
    if (!hero) return;
    renderFounder();
  }

  function setFounderTheme(enabled) {
    founderEnabled = Boolean(enabled);
    if (!founderEnabled) {
      removeFounderTreatment();
    } else {
      updateHero(mountedSlot || document.querySelector(SLOT_SELECTOR));
    }
  }

  function exactEffortMenu() {
    // Live DSH is a drill-down: the SAME menu container (aria-label "Model and
    // reasoning effort") first shows Model/Effort rows, then swaps to Off/High/Max
    // radios after the Effort row is clicked. So the effort menu is identified by
    // containing effort radios, not by exclusion of the label.
    return Array.from(document.querySelectorAll('div[role="menu"]')).find((menu) => {
      if (!isVisible(menu)) return false;
      const radios = menu.querySelectorAll('button[role="menuitemradio"]');
      return radios.length > 0 && Array.from(radios).some((button) => exactRadio(menu, normalize(button.textContent)) || normalize(button.textContent) === "Off" || normalize(button.textContent) === "High" || normalize(button.textContent) === "Max");
    }) || null;
  }

  function visibleMenus() {
    return Array.from(document.querySelectorAll('div[role="menu"]')).filter(isVisible);
  }

  function exactRadio(menu, label) {
    return Array.from(menu.querySelectorAll('button[role="menuitemradio"]')).find((button) => {
      const ariaLabel = normalize(button.getAttribute("aria-label"));
      const text = normalize(button.textContent);
      return ariaLabel === label || text === label;
    }) || null;
  }

  function effortRow(menu) {
    // Live DSH renders the row as a cell whose textContent is "Effort" + the current
    // value (e.g. "EffortMax"). Match on the dedicated label span, not full text.
    const candidates = Array.from(menu.querySelectorAll('button, [role="menuitem"], [role="option"], div'));
    return candidates.find((candidate) => {
      if (candidate.matches('button[role="menuitemradio"]')) return false;
      const labelSpan = candidate.querySelector(':scope > span');
      return normalize(labelSpan && labelSpan.textContent) === "Effort" || normalize(candidate.getAttribute("aria-label")) === "Effort" || normalize(candidate.textContent) === "Effort";
    }) || null;
  }

  function waitFor(read, timeout = 1500) {
    return new Promise((resolve, reject) => {
      const started = performance.now();
      const check = () => {
        const result = read();
        if (result) return resolve(result);
        if (performance.now() - started >= timeout) return reject(new Error("DSH effort menu did not appear"));
        window.setTimeout(check, 20);
      };
      check();
    });
  }

  async function selectNativeEffort(label) {
    const trigger = modelTrigger();
    if (!trigger) throw new Error("DSH model selector is unavailable");
    trigger.click();

    let effortMenu = exactEffortMenu();
    if (!effortMenu) {
      // Top menu is identified structurally (it contains an Effort row), because
      // live DSH labels BOTH levels "Model and reasoning effort".
      const modelMenu = await waitFor(() => visibleMenus().find((menu) => effortRow(menu)));
      const row = effortRow(modelMenu);
      if (!row) throw new Error("DSH effort row is unavailable");
      row.click();
      effortMenu = await waitFor(exactEffortMenu);
    }

    const radio = exactRadio(effortMenu, label);
    if (!radio) throw new Error(`DSH effort option ${label} is unavailable`);
    radio.click();
    await waitFor(() => readNativeLevel(trigger) === label);
  }

  async function applyNativeEffortWithRetry(label) {
    // Menus animate in live DSH and the event loop can stall briefly; a single
    // 1500ms pass gave up permanently (observed as stuck-unavailable under
    // load). Re-clicking the trigger toggles any half-open menu closed, so
    // retries are self-cleaning and idempotent.
    let lastError = null;
    for (let attempt = 0; attempt < 3; attempt += 1) {
      try {
        await selectNativeEffort(label);
        return;
      } catch (error) {
        lastError = error;
        await new Promise((resolve) => window.setTimeout(resolve, 240));
      }
    }
    throw lastError;
  }

  function scheduleApply() {
    if (level === null) return;
    desiredLevel = LEVELS[level];
    window.clearTimeout(applyTimer);
    applyTimer = window.setTimeout(flushApply, 70);
  }

  async function flushApply() {
    if (applying || !desiredLevel) return;
    const requested = desiredLevel;
    desiredLevel = null;
    const previous = confirmedLevel;
    applying = true;
    try {
      await applyNativeEffortWithRetry(requested);
      confirmedLevel = requested;
      level = LEVELS.indexOf(requested);
      unavailable = false;
    } catch (_error) {
      desiredLevel = null;
      level = confirmedLevel === null ? null : LEVELS.indexOf(confirmedLevel);
      unavailable = true;
      if (previous === null) confirmedLevel = null;
    } finally {
      applying = false;
      renderRail();
      updateAccent();
      updateHero(mountedSlot);
      if (desiredLevel && desiredLevel !== confirmedLevel) scheduleApply();
    }
  }

  function reconcile() {
    const slot = document.querySelector(SLOT_SELECTOR);
    const trigger = modelTrigger();
    if (!slot || !trigger) {
      detachRail();
      removeFounderTreatment();
      return;
    }

    mountRail(slot, trigger);
    const nativeLevel = readNativeLevel(trigger);
    if (nativeLevel && (!applying || nativeLevel === desiredLevel)) {
      if (confirmedLevel !== nativeLevel) {
        confirmedLevel = nativeLevel;
        level = LEVELS.indexOf(nativeLevel);
        unavailable = false;
      }
    }
    updateHero(slot);
    renderRail();
    updateAccent();
  }

  function scheduleReconcile() {
    if (reconcileTimer) return;
    reconcileTimer = window.setTimeout(() => {
      reconcileTimer = null;
      reconcile();
    }, 40);
  }

  function destroy() {
    window.clearTimeout(reconcileTimer);
    window.clearTimeout(applyTimer);
    window.clearTimeout(tooltipTimer);
    window.clearInterval(interval);
    if (observer) observer.disconnect();
    detachRail();
    removeFounderTreatment();
    document.getElementById(STYLE_ID)?.remove();
    window.__DSH_EFFORT_CONTROL__ = null;
  }

  installStyle();
  observer = new MutationObserver(scheduleReconcile);
  observer.observe(document.documentElement, {
    subtree: true,
    childList: true,
    attributes: true,
    attributeFilter: ["aria-label", "data-dsh-view", "data-page", "data-view", "data-testid", "data-conversation-id", "data-message-id"],
  });
  interval = window.setInterval(reconcile, 700);
  window.__DSH_EFFORT_CONTROL__ = { destroy, setFounderTheme };
  reconcile();
})();
