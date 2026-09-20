import assert from "node:assert/strict";
import { mkdir, mkdtemp, readFile, writeFile } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join, resolve } from "node:path";
import { pathToFileURL } from "node:url";

const cyberfox1337x = Object.freeze({ function: name => void name });
cyberfox1337x.function("dawnwalker_layout_verification");
const modulePath = process.argv[2];
if (!modulePath) throw new Error("Pass the external Playwright index.mjs path.");
const phase = process.argv.includes("--baseline") ? "baseline" : "final";
const packaged = process.argv.includes("--packaged");
const evidenceLabel = process.argv.find(argument => argument.startsWith("--evidence-label="))?.slice("--evidence-label=".length) || "";
if (evidenceLabel && !/^[a-z0-9][a-z0-9-]*$/i.test(evidenceLabel)) throw new Error("Evidence label must contain only letters, digits, and hyphens.");
const evidenceSuffix = evidenceLabel ? `-${evidenceLabel}` : "";
const { _electron } = await import(pathToFileURL(resolve(modulePath)).href);
const root = process.cwd();
const releaseDirectory = resolve(root, process.argv.find(argument => argument.startsWith("--release-directory="))?.slice("--release-directory=".length) || "release-qa");
const scratch = await mkdtemp(join(tmpdir(), "dawnwalker-layout-"));
const app = await _electron.launch({
  executablePath: packaged ? join(releaseDirectory, "win-unpacked/Blood of Dawnwalker Mod Menu.exe") : join(root, "node_modules/electron/dist/electron.exe"),
  args: [...(packaged ? [] : [root]), `--user-data-dir=${join(scratch, "profile")}`],
  cwd: root,
  env: { ...process.env, LOCALAPPDATA: join(scratch, "Local"), APPDATA: join(scratch, "Roaming"), DAWNWALKER_CAPTURE_PATH: "", DAWNWALKER_DEV_URL: "", DAWNWALKER_ENABLE_PILOT_CONTROLS: "" },
});
const evidence = { capturedAtUtc: new Date().toISOString(), phase, packaged, gameplayVerified: false, isolatedProfile: scratch, cases: [], interactions: [], rendererErrors: [] };
let closedByButton = false;
const outputDirectory = join(root, "visual-qa", `layout-${phase}${packaged ? "-packaged" : ""}${evidenceSuffix}`);
await mkdir(outputDirectory, { recursive: true });

// Compare actual browser geometry. Scrolled content can be outside its viewport;
// its own rows must still fit horizontally and avoid sibling overlap.
async function inspect(page) {
  return page.evaluate(() => {
    const issues = [];
    const box = element => { const { x, y, width, height, right, bottom } = element.getBoundingClientRect(); return { x, y, width, height, right, bottom }; };
    const visible = element => Boolean(element.getClientRects().length) && getComputedStyle(element).visibility !== "hidden";
    const label = element => element.getAttribute("aria-label") || `${element.tagName.toLowerCase()}.${String(element.className).split(" ").join(".")}`;
    const overlap = (a, b) => Math.min(a.right, b.right) - Math.max(a.x, b.x) > 1 && Math.min(a.bottom, b.bottom) - Math.max(a.y, b.y) > 1;
    const stage = box(document.querySelector(".app-stage"));
    const readingText = [...document.querySelectorAll(".feature-tools p, .feature-tools h4, .capability-notice p, .control-row > span:first-child, .credit-entry a, .left-rail button")].filter(visible);
    const minimumReadingSize = readingText.length ? Math.min(...readingText.map(element => parseFloat(getComputedStyle(element).fontSize) * stage.width / 1672)) : null;
    if (minimumReadingSize !== null && minimumReadingSize < 11.99) issues.push(`Reading text shrinks below 12px (${minimumReadingSize.toFixed(2)}px)`);
    if (stage.x < -1 || stage.y < -1 || stage.right > innerWidth + 1 || stage.bottom > innerHeight + 1) issues.push("Stage extends beyond viewport");
    const preset = document.querySelector(".preset-select");
    const presetSelect = preset.querySelector("select");
    const presetStyle = getComputedStyle(presetSelect);
    const presetArrow = box(preset.querySelector("svg"));
    const presetBox = box(preset);
    if (presetStyle.textAlign !== "center" || presetStyle.textAlignLast !== "center") issues.push("Preset text is not centered");
    if (Math.abs(presetArrow.y + presetArrow.height / 2 - presetBox.y - presetBox.height / 2) > 1.5) issues.push("Preset chevron is not vertically centered");
    const presetButton = document.querySelector(".preset-controls button");
    const captionRange = document.createRange();
    const caption = presetButton.querySelector("span");
    if (caption) captionRange.selectNodeContents(caption);
    else {
      const textNode = [...presetButton.childNodes].find(node => node.nodeType === Node.TEXT_NODE && node.textContent.trim());
      captionRange.selectNodeContents(textNode);
    }
    const captionRects = [...captionRange.getClientRects()].filter(rect => rect.width > 0);
    if (captionRects.length !== 1) issues.push("Save UI Preset caption wraps");
    const iconBox = box(presetButton.querySelector("svg"));
    const captionBox = captionRange.getBoundingClientRect();
    const buttonBox = box(presetButton);
    const groupLeft = Math.min(iconBox.x, captionBox.x);
    const groupRight = Math.max(iconBox.right, captionBox.right);
    if (Math.abs((groupLeft + groupRight) / 2 - buttonBox.x - buttonBox.width / 2) > 1.5) issues.push("Save UI Preset icon and caption are not horizontally centered");
    if (Math.abs(iconBox.y + iconBox.height / 2 - buttonBox.y - buttonBox.height / 2) > 1.5) issues.push("Save UI Preset icon is not vertically centered");
    for (const selector of [".toolbar", ".preset-controls", ".left-rail button", ".category-view .panel-content", ".category-section", ".control-row", ".settings-summary", ".feature-tools", ".feature-fields", ".credit-grid", ".feature-actions"]) {
      for (const parent of document.querySelectorAll(selector)) {
        if (!visible(parent)) continue;
        if (parent.scrollWidth > parent.clientWidth + 2) issues.push(`${label(parent)} has horizontal overflow (${parent.scrollWidth}/${parent.clientWidth})`);
        const children = [...parent.children].filter(element => visible(element) && !element.classList.contains("sr-only"));
        for (let index = 0; index < children.length; index += 1) {
          const child = children[index]; const rect = box(child); const bounds = box(parent);
          if (rect.x < bounds.x - 2 || rect.right > bounds.right + 2) issues.push(`${label(child)} extends outside ${label(parent)}`);
          if (!parent.classList.contains("panel-content") && (rect.y < bounds.y - 2 || rect.bottom > bounds.bottom + 2)) issues.push(`${label(child)} extends vertically outside ${label(parent)}`);
          for (const next of children.slice(index + 1)) if (overlap(rect, box(next))) issues.push(`${label(child)} overlaps ${label(next)} in ${label(parent)}`);
        }
      }
    }
    const toast = document.querySelector(".toast-visible");
    if (toast) {
      const toastBox = box(toast);
      const toastText = document.createRange();
      toastText.selectNodeContents(toast);
      const textBox = toastText.getBoundingClientRect();
      if (toast.textContent.length < 50 && toastBox.width - textBox.width > 50 * stage.width / 1672) issues.push("Short notification stretches beyond its text");
      for (const panel of document.querySelectorAll(".panel:not([hidden]), .right-rail, .hotkey-note")) {
        if (visible(panel) && overlap(toastBox, box(panel))) issues.push(`Notification obscures ${label(panel)}`);
      }
    }
    return { viewport: [innerWidth, innerHeight], stage, minimumReadingSize, issues: [...new Set(issues)] };
  });
}

try {
  const page = await app.firstWindow();
  await app.evaluate(({ BrowserWindow }) => BrowserWindow.getAllWindows()[0].webContents.setBackgroundThrottling(false));
  page.on("pageerror", error => evidence.rendererErrors.push(error.message));
  await page.waitForSelector(".app-stage");
  await page.evaluate(() => document.fonts.ready);
  const profile = await app.evaluate(({ app: electronApp }) => electronApp.getPath("userData"));
  assert.ok(profile.toLowerCase().startsWith(scratch.toLowerCase()));
  const categories = ["Player", "Combat", "World", "Teleport", "Visuals", "NPC", "Quests", "Save Editor", "Settings"];
  const categoryButton = category => page.locator(".left-rail").getByRole("button", { name: category, exact: true });
  const runtimeInfo = await page.evaluate(() => window.dawnwalkerDesktop.getRuntimeInfo());
  const manifest = await readFile(join(process.env["ProgramFiles(x86)"] || "C:\\Program Files (x86)", "Steam/steamapps/appmanifest_3751260.acf"), "utf8");
  const installedBuildId = manifest.match(/"buildid"\s+"(\d+)"/)[1];
  assert.equal(runtimeInfo.installedBuildId, installedBuildId);
  assert.equal(await page.locator(".menu-status").count(), 0);
  assert.equal(await page.getByRole("region", { name: "Menu status", exact: true }).count(), 0);
  await page.waitForFunction(build => document.querySelector(".version")?.textContent.includes(`Game build ${build}`), installedBuildId);
  assert.match(await page.locator(".version").innerText(), new RegExp(`Game build ${installedBuildId}`));
  assert.equal(await page.getByText("Player Info", { exact: true }).count(), 0);
  evidence.buildIdentity = { installedBuildId, verifiedBuildId: runtimeInfo.verifiedBuildId, buildVerified: runtimeInfo.buildVerified, interactionEligible: runtimeInfo.interactionEligible };
  evidence.interactions.push("Menu Status box is removed; installed Steam build remains in the footer without changing runtime authorization");
  assert.equal(await page.locator(".top-tabs").count(), 0);
  assert.equal(await page.getByRole("tab").count(), 0);
  assert.equal(await page.getByText("DRAG WINDOW", { exact: true }).count(), 0);
  assert.equal((await page.locator(".window-drag-handle").textContent()).trim(), "");
  assert.equal(await page.getByText("Console and mod loading", { exact: true }).count(), 0);
  assert.equal(await page.getByText("Runtime and documentation", { exact: true }).count(), 0);
  assert.equal(await page.locator(".supporting-reference").count(), 0);
  evidence.interactions.push("Redundant top category strip, visible drag label, console notice, and runtime/documentation block are absent");
  const sizes = [[1100, 620, 1], [1366, 768, 1], [1672, 941, 1], [1920, 1080, 1], [2560, 1440, 1], [1672, 941, 1.5]];
  for (const [width, height, zoom] of sizes) {
    await app.evaluate(({ BrowserWindow }, size) => { const window = BrowserWindow.getAllWindows()[0]; window.setSize(size.width, size.height); window.webContents.setZoomFactor(size.zoom); }, { width, height, zoom });
    for (const category of categories) {
      await categoryButton(category).click();
      assert.equal(await categoryButton(category).getAttribute("aria-current"), "page");
      assert.equal(await page.locator('.left-rail button[aria-current="page"]').count(), 1);
      const panel = page.locator(`#panel-${category.toLowerCase().replaceAll(" ", "-")}`);
      await panel.waitFor({ state: "visible" });
      if (category === "Player") {
        assert.equal(await page.locator(".right-rail").count(), 0);
        assert.equal(await page.locator(".app-stage.has-context-rail").count(), 0);
      }
      if (category === "Visuals") {
        assert.equal(await panel.getByText("Eye appearance unavailable", { exact: true }).count(), 1);
        assert.equal(await panel.locator(".panel-content > *").count(), 1);
        assert.equal(await panel.getByRole("region", { name: "Fog configuration" }).count(), 0);
        assert.equal(await panel.getByText("HUD Visible", { exact: true }).count(), 0);
      }
      if (category === "Settings") {
        assert.equal(await panel.locator(".settings-summary").count(), 0);
        assert.equal(await panel.getByText("Local settings only", { exact: true }).count(), 0);
      }
      await page.evaluate(() => Promise.all(document.getAnimations().map(animation => animation.finished.catch(() => {}))));
      await panel.locator(".panel-content").evaluate(element => { element.scrollTop = 0; });
      const name = `${width}x${height}-zoom${zoom}-${category.toLowerCase()}`;
      const result = { name, category, requestedWindow: [width, height], zoom, ...await inspect(page), scrollBottomIssues: [], screenshots: [] };
      const capture = (width === 1672 && zoom === 1) || width === 1100;
      if (capture) { const path = join(outputDirectory, `${name}.png`); await page.screenshot({ path }); result.screenshots.push(path); }
      const scrolled = await panel.locator(".panel-content").evaluate(element => { element.scrollTop = element.scrollHeight; return element.scrollTop > 0; });
      if (scrolled) {
        result.scrollBottomIssues = (await inspect(page)).issues;
        if (capture) { const path = join(outputDirectory, `${name}-bottom.png`); await page.screenshot({ path }); result.screenshots.push(path); }
      }
      evidence.cases.push(result);
    }
  }
  await app.evaluate(({ BrowserWindow }) => { const window = BrowserWindow.getAllWindows()[0]; window.setSize(1672, 941); window.webContents.setZoomFactor(1); });
  for (const category of categories) {
    await categoryButton(category).click();
    await page.getByLabel("Search menu options").fill("__nothing_matches_qa__");
    await page.getByText(`No matching ${category} controls`, { exact: true }).waitFor();
    await page.getByRole("button", { name: "Clear search", exact: true }).click();
    assert.equal(await page.getByLabel("Search menu options").inputValue(), "");
  }
  evidence.interactions.push("Sidebar navigation, active-category state, and empty-search recovery passed for all nine pages");
  await categoryButton("Settings").click();
  await page.getByLabel("Search menu options").fill("credits");
  assert.equal(await page.locator("#panel-settings .credit-entry").count(), 7);
  assert.equal(await page.locator("#panel-settings .supporting-reference").count(), 0);
  assert.equal(await page.getByText("Runtime and documentation", { exact: true }).count(), 0);
  assert.equal(await page.getByText("Console and mod loading", { exact: true }).count(), 0);
  assert.equal(await page.getByText("DRAG WINDOW", { exact: true }).count(), 0);
  evidence.interactions.push("Settings retains all seven creator credit entries after removing the requested panels");
  await page.getByRole("button", { name: "Save UI Preset", exact: true }).click();
  await page.getByLabel("Local UI preset").selectOption("Default Preset");
  assert.equal(await categoryButton("Player").getAttribute("aria-current"), "page");
  await page.reload();
  await page.getByLabel("Local UI preset").selectOption("Custom Preset");
  assert.equal(await page.getByLabel("Search menu options").inputValue(), "credits");
  assert.equal(await categoryButton("Settings").getAttribute("aria-current"), "page");
  await page.getByLabel("Search menu options").fill("reset ui view");
  await page.getByRole("button", { name: "Reset UI View", exact: true }).click();
  assert.equal(await categoryButton("Player").getAttribute("aria-current"), "page");
  evidence.interactions.push("Preset save, reload persistence, restore, and Reset UI View passed");
  await page.getByRole("button", { name: "Minimize application", exact: true }).click();
  for (let attempt = 0; attempt < 20; attempt += 1) {
    if (await app.evaluate(({ BrowserWindow }) => BrowserWindow.getAllWindows()[0].isMinimized())) break;
    await new Promise(resolveWait => setTimeout(resolveWait, 50));
  }
  assert.equal(await app.evaluate(({ BrowserWindow }) => BrowserWindow.getAllWindows()[0].isMinimized()), true);
  await app.evaluate(({ BrowserWindow }) => { const window = BrowserWindow.getAllWindows()[0]; window.restore(); window.show(); });
  assert.equal(await app.evaluate(({ BrowserWindow }) => BrowserWindow.getAllWindows()[0].isMinimized()), false);
  evidence.interactions.push("Actual minimize button minimized the native window; restoration retained the app");
  const closing = page.waitForEvent("close");
  await page.getByRole("button", { name: "Close application", exact: true }).click();
  await closing;
  closedByButton = true;
  evidence.interactions.push("Actual Close application button closed the native window");
  assert.deepEqual(evidence.rendererErrors, []);
  evidence.issueCount = evidence.cases.reduce((sum, entry) => sum + entry.issues.length + entry.scrollBottomIssues.length, 0);
  const artifact = join(root, "qa", `dawnwalker-layout-${phase}${packaged ? "-packaged" : ""}-20260906${evidenceSuffix}.json`);
  await writeFile(artifact, JSON.stringify(evidence, null, 2));
  console.log(JSON.stringify({ artifact, cases: evidence.cases.length, issues: evidence.issueCount, uniqueIssues: [...new Set(evidence.cases.flatMap(entry => [...entry.issues, ...entry.scrollBottomIssues]))], interactions: evidence.interactions }, null, 2));
  if (phase === "final") assert.equal(evidence.issueCount, 0, "Layout issues remain; review the evidence and screenshots.");
} finally { if (!closedByButton) await app.close(); }
