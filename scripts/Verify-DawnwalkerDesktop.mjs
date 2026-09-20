import assert from "node:assert/strict";
import { createHash } from "node:crypto";
import { cp, mkdir, mkdtemp, readFile, writeFile } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join, resolve } from "node:path";
import { pathToFileURL } from "node:url";

const cyberfox1337x = Object.freeze({ function: name => void name });
cyberfox1337x.function("dawnwalker_desktop_verification");

const modulePath = process.argv[2];
if (!modulePath) throw new Error("Pass an installed Playwright index.mjs path; no project dependency is required.");
const { _electron } = await import(pathToFileURL(resolve(modulePath)).href);
const root = process.cwd();
const releaseDirectory = resolve(root, process.argv.find(argument => argument.startsWith("--release-directory="))?.slice("--release-directory=".length) || "release-qa");
const packaged = process.argv.includes("--packaged");
const evidenceLabel = process.argv.find(argument => argument.startsWith("--evidence-label="))?.slice("--evidence-label=".length) || "";
if (evidenceLabel && !/^[a-z0-9][a-z0-9-]*$/i.test(evidenceLabel)) throw new Error("Evidence label must contain only letters, digits, and hyphens.");
const evidenceSuffix = evidenceLabel ? `-${evidenceLabel}` : "";
const screenshotPrefix = `${packaged ? "packaged-feature" : "feature"}${evidenceSuffix}`;
const scratch = await mkdtemp(join(tmpdir(), "dawnwalker-desktop-verification-"));
const local = join(scratch, "Local");
const saves = join(local, "Dawnwalker", "Saved", "SaveGames");
await mkdir(saves, { recursive: true });
const sourceSaves = join(process.env.LOCALAPPDATA, "Dawnwalker", "Saved", "SaveGames");
for (const extension of ["sav", "meta", "png"]) await cp(join(sourceSaves, `ManualSave2.${extension}`), join(saves, `ManualSave2.${extension}`));
const originalSave = await readFile(join(saves, "ManualSave2.sav"));
const evidence = { capturedAt: new Date().toISOString(), packaged, gameplayVerified: false, fixtureDirectory: scratch, checks: [], screenshots: [] };
const launched = await _electron.launch({
  executablePath: packaged ? join(releaseDirectory, "win-unpacked", "Blood of Dawnwalker Mod Menu.exe") : join(root, "node_modules", "electron", "dist", "electron.exe"),
  args: [...(packaged ? [] : [root]), `--user-data-dir=${join(scratch, "profile")}`],
  cwd: root,
  env: { ...process.env, LOCALAPPDATA: local, APPDATA: join(scratch, "Roaming"), DAWNWALKER_ENABLE_PILOT_CONTROLS: "1", DAWNWALKER_CAPTURE_PATH: "", DAWNWALKER_DEV_URL: "" },
});
try {
  const page = await launched.firstWindow();
  const rendererErrors = [];
  page.on("pageerror", error => rendererErrors.push(error.message));
  await page.waitForSelector(".app-stage");
  const categoryButton = category => page.locator(".left-rail").getByRole("button", { name: category, exact: true });
  const profile = await launched.evaluate(({ app }) => app.getPath("userData"));
  assert.ok(profile.toLowerCase().startsWith(scratch.toLowerCase()), `Unsafe QA profile: ${profile}`);
  const status = await page.evaluate(() => window.dawnwalkerDesktop.getRuntimeInfo());
  assert.equal(status.interactionEligible, false);
  assert.match(status.compatibilityIssue, /25129649|build|identity/i);
  const rejected = await page.evaluate(() => window.dawnwalkerDesktop.dispatch({ capability: "player:god-mode", value: true, requestId: "qa-mismatch", sessionId: "unverified" }));
  assert.equal(rejected.accepted, false);
  assert.equal(rejected.message, status.compatibilityIssue);
  evidence.checks.push("Real installed build mismatch blocks main-process runtime readbacks and dispatch despite pilot flag");

  await categoryButton("Visuals").click();
  await page.getByText("Eye appearance unavailable", { exact: true }).waitFor();
  assert.equal(await page.locator("#panel-visuals .panel-content > *").count(), 1);
  assert.equal(await page.getByRole("region", { name: "Fog configuration", exact: true }).count(), 0);
  assert.equal(await page.locator(".menu-status").count(), 0);
  assert.equal(await page.locator(".settings-summary").count(), 0);
  evidence.checks.push("Visuals contains only Eye Appearance; Fog, HUD, Menu Status and Settings information blocks are absent");
  await mkdir(join(root, "visual-qa"), { recursive: true });
  await page.screenshot({ path: join(root, "visual-qa", `${screenshotPrefix}-visuals-desktop.png`) });
  evidence.screenshots.push(`visual-qa/${screenshotPrefix}-visuals-desktop.png`);

  await categoryButton("Save Editor").click();
  await page.getByLabel("Search menu options").fill("save tools");
  await page.getByLabel("Selected save", { exact: true }).selectOption("ManualSave2.sav");
  await page.getByText("Compressed save structure decoded and verified.", { exact: false }).waitFor();
  evidence.checks.push("Selected real save copy is decoded and validated through renderer/preload/IPC without claiming editable field semantics");
  await page.getByRole("button", { name: "Create verified backup" }).click();
  await page.getByText("Backup verified:", { exact: false }).waitFor();
  await page.getByRole("button", { name: "Review restoration" }).click();
  await page.getByRole("region", { name: "Pending restoration" }).waitFor();
  await page.getByRole("button", { name: "Back up current files & restore" }).click();
  await page.getByText("Exact backup bytes restored and verified.", { exact: false }).waitFor();
  assert.deepEqual(await readFile(join(saves, "ManualSave2.sav")), originalSave);
  evidence.checks.push("Actual save selection, verified backup, pending restoration and recovery through IPC on copied real save");
  await page.screenshot({ path: join(root, "visual-qa", `${screenshotPrefix}-save-desktop.png`) });
  evidence.screenshots.push(`visual-qa/${screenshotPrefix}-save-desktop.png`);
  await launched.evaluate(({ BrowserWindow }) => BrowserWindow.getAllWindows()[0].setSize(1100, 650));
  await page.screenshot({ path: join(root, "visual-qa", `${screenshotPrefix}-save-narrow.png`) });
  evidence.screenshots.push(`visual-qa/${screenshotPrefix}-save-narrow.png`);
  await launched.evaluate(({ BrowserWindow }) => BrowserWindow.getAllWindows()[0].setSize(1672, 941));

  await categoryButton("Settings").click();
  await page.getByPlaceholder("Search settings…").fill("credits");
  assert.equal(await page.locator(".credit-entry").count(), 7);
  assert.equal(await page.locator(".supporting-reference").count(), 0);
  assert.equal(await page.getByText("Runtime and documentation", { exact: true }).count(), 0);
  const links = await page.locator(".credit-entry a").evaluateAll(elements => elements.map(element => element.href));
  assert.equal(links.length, 7);
  assert.equal(new Set(links).size, 7);
  await launched.evaluate(({ shell }) => { globalThis.__qaLinks = []; shell.openExternal = async url => { globalThis.__qaLinks.push(url); }; });
  for (const link of await page.locator(".credit-entry a").all()) await link.click();
  const openedLinks = await launched.evaluate(() => globalThis.__qaLinks);
  assert.deepEqual(openedLinks, links);
  const invalidLinkRejected = await page.evaluate(async () => { try { await window.dawnwalkerDesktop.openFeatureReference(999); return false; } catch { return true; } });
  assert.equal(invalidLinkRejected, true);
  evidence.checks.push("All seven creator credit links traverse IPC to allowlisted shell opener; runtime/documentation block is absent; OS browser opening stubbed; unknown ID rejected");
  await page.locator("#panel-settings .panel-content").evaluate(element => { element.scrollTop = 0; });
  await page.screenshot({ path: join(root, "visual-qa", `${screenshotPrefix}-credits-desktop.png`) });
  evidence.screenshots.push(`visual-qa/${screenshotPrefix}-credits-desktop.png`);
  await launched.evaluate(({ BrowserWindow }) => BrowserWindow.getAllWindows()[0].setSize(1100, 650));
  await page.screenshot({ path: join(root, "visual-qa", `${screenshotPrefix}-credits-narrow.png`) });
  evidence.screenshots.push(`visual-qa/${screenshotPrefix}-credits-narrow.png`);
  assert.deepEqual(rendererErrors, []);
  evidence.checks.push("No renderer errors; desktop and 1100×650 screenshots captured");
  evidence.fixtureSaveSha256 = createHash("sha256").update(originalSave).digest("hex");
  await writeFile(join(root, "qa", `dawnwalker-desktop-integration${packaged ? "-packaged" : ""}-20260906${evidenceSuffix}.json`), JSON.stringify(evidence, null, 2));
  console.log(JSON.stringify({ passed: evidence.checks, screenshots: evidence.screenshots }, null, 2));
} finally { await launched.close(); }
