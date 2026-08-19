#!/usr/bin/env python3
"""Bounded browser fixture for the DSH effort-control DOM contract."""

from __future__ import annotations

import argparse
from pathlib import Path

from playwright.sync_api import Error as PlaywrightError
from playwright.sync_api import sync_playwright


ONE_PIXEL_PNG = "data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII="


def run(script_path: Path) -> None:
    script = script_path.read_text(encoding="utf-8")
    script = script.replace("__DSH_FOUNDER_THEME_ENABLED__", "true")
    placeholders = (
        "__DSH_FOUNDER_OFF_DATA_URI__",
        "__DSH_FOUNDER_HIGH_DATA_URI__",
        "__DSH_FOUNDER_MAX_DATA_URI__",
    )
    for placeholder in placeholders:
        script = script.replace(placeholder, ONE_PIXEL_PNG)
    assert all(placeholder not in script for placeholder in placeholders)

    html = """
    <!doctype html>
    <html data-theme="light">
      <head><meta charset="utf-8"><title>DSH fixture</title></head>
      <body class="light">
        <aside class="sidebar">
          <button id="sidebar-new-session" aria-label="New Session">New Session</button>
        </aside>
        <main id="new-session-main" data-dsh-view="new-session">
          <section class="hero-content">
            <div class="trailing-row">
              <div data-slot="conversation.input.right"></div>
              <div data-slot="conversation.input.model">
                <button id="model-trigger" aria-label="Select model · reasoning effort Off">DeepSeek</button>
                <button id="send-button" aria-label="Send message">Send</button>
              </div>
            </div>
          </section>
          <div id="stale-marker" data-testid="new-session" hidden>stale marker</div>
        </main>
        <script>
          const trigger = document.querySelector('#model-trigger');
          let modelMenu;
          let effortMenu;
          const levels = ['Off', 'High', 'Max'];
          function closeMenus() {
            modelMenu?.remove();
            effortMenu?.remove();
            modelMenu = undefined;
            effortMenu = undefined;
          }
          trigger.addEventListener('click', () => {
            closeMenus();
            modelMenu = document.createElement('div');
            modelMenu.setAttribute('role', 'menu');
            modelMenu.setAttribute('aria-label', 'Model menu');
            const effort = document.createElement('button');
            effort.setAttribute('role', 'menuitem');
            effort.textContent = 'Effort';
            effort.addEventListener('click', () => {
              effortMenu = document.createElement('div');
              effortMenu.setAttribute('role', 'menu');
              effortMenu.setAttribute('aria-label', 'Model and reasoning effort');
              levels.forEach((level) => {
                const option = document.createElement('button');
                option.setAttribute('role', 'menuitemradio');
                option.setAttribute('aria-checked', level === trigger.getAttribute('aria-label').split(' ').pop());
                option.textContent = level;
                option.addEventListener('click', () => {
                  trigger.setAttribute('aria-label', `Select model · reasoning effort ${level}`);
                  closeMenus();
                });
                effortMenu.append(option);
              });
              document.body.append(effortMenu);
              modelMenu.remove();
            });
            modelMenu.append(effort);
            document.body.append(modelMenu);
          });
        </script>
      </body>
    </html>
    """

    errors: list[str] = []
    with sync_playwright() as playwright:
        try:
            browser = playwright.chromium.launch(headless=True)
        except PlaywrightError as error:
            raise RuntimeError(
                "Playwright Chromium could not launch in this host sandbox; run this gate from a normal macOS shell."
            ) from error
        page = browser.new_page(viewport={"width": 1024, "height": 768})
        page.on("pageerror", lambda error: errors.append(str(error)))
        page.set_content(html)
        page.add_script_tag(content=script)

        rail = page.locator('[data-dsh-effort-control]')
        rail.wait_for(state="visible")
        effort_input = rail.locator('input[type="range"]')
        assert effort_input.get_attribute("aria-label") == "Reasoning effort"
        assert effort_input.get_attribute("aria-valuetext") == "Off"
        assert rail.locator('[role="tooltip"]').inner_text() == "Reasoning · Off"
        assert page.locator('[data-dsh-effort-hero]').count() == 1
        assert page.locator("main#new-session-main[data-dsh-effort-hero]").count() == 1
        assert page.locator("#sidebar-new-session[data-dsh-effort-hero]").count() == 0
        assert page.locator("#stale-marker[data-dsh-effort-hero]").count() == 0
        page.wait_for_function("Array.from(document.querySelectorAll('.dsh-effort-founder-layer')).some(layer => layer.style.backgroundImage.includes('data:image/png'))")

        effort_input.focus()
        effort_input.press("ArrowRight")
        page.wait_for_function("document.querySelector('#model-trigger').getAttribute('aria-label').endsWith('High')")
        assert effort_input.get_attribute("aria-valuetext") == "High"

        effort_input.press("ArrowRight")
        page.wait_for_function("document.querySelector('#model-trigger').getAttribute('aria-label').endsWith('Max')")
        assert effort_input.get_attribute("aria-valuetext") == "Max"
        assert page.locator('.dsh-effort-control').evaluate("element => getComputedStyle(element).getPropertyValue('--dsh-effort-accent').trim()") == "#c69b3c"

        page.locator("#model-trigger").click()
        page.get_by_role("menuitem", name="Effort").click()
        page.get_by_role("menuitemradio", name="Off", exact=True).click()
        page.wait_for_function("document.querySelector('[data-dsh-effort-control] input').getAttribute('aria-valuetext') === 'Off'")

        page.locator("main").evaluate(
            "(element, [attribute, value]) => element.setAttribute(attribute, value)",
            ["data-dsh-view", "conversation"],
        )
        page.locator("main").evaluate(
            "(element, [attribute, value]) => element.setAttribute(attribute, value)",
            ["data-message-id", "message-1"],
        )
        page.wait_for_function("document.querySelector('[data-dsh-effort-hero]') === null")
        assert page.locator("[data-dsh-effort-hero]").count() == 0
        assert page.locator("html").get_attribute("data-theme") == "light"
        body_classes = (page.locator("body").get_attribute("class") or "").split()
        assert "light" in body_classes
        assert "dark" not in body_classes

        # v3.1 founder-theme toggle contract: off removes the hero layer, on restores it.
        page.wait_for_function("window.__DSH_EFFORT_CONTROL__ && typeof window.__DSH_EFFORT_CONTROL__.setFounderTheme === 'function'")
        page.evaluate("window.__DSH_EFFORT_CONTROL__.setFounderTheme(false)")
        page.wait_for_function("document.querySelector('[data-dsh-effort-hero]') === null")
        assert page.locator(".dsh-effort-founder-layer").count() == 0
        page.locator("main").evaluate("element => element.removeAttribute('data-message-id')")
        page.locator("main").evaluate("element => element.setAttribute('data-dsh-view', 'new-session')")
        page.evaluate("window.__DSH_EFFORT_CONTROL__.setFounderTheme(true)")
        page.wait_for_function("document.querySelector('[data-dsh-effort-hero]') !== null")
        assert page.locator(".dsh-effort-founder-layer").count() == 2
        assert not errors, errors
        browser.close()


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--script", type=Path, required=True)
    args = parser.parse_args()
    try:
        run(args.script)
    except RuntimeError as error:
        print(f"ERROR: {error}")
        raise SystemExit(1) from None
    print("DOM fixture passed")
