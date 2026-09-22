#!/usr/bin/env node
// Kimi Status Bar uninstaller: removes the hooks from ~/.kimi-code/config.toml,
// deletes ~/.kimi-code/statusbar/, quits and removes the app. Everything else in
// config.toml is left intact. Safe to run even if nothing is installed.

const fs = require("fs");
const os = require("os");
const path = require("path");
const cp = require("child_process");

const home = os.homedir();
const sbDir = path.join(home, ".kimi-code", "statusbar");
const configPath = path.join(home, ".kimi-code", "config.toml");
const MARKER = sbDir;
const APP = "/Applications/KimiStatusBar.app";

try { cp.execSync("pkill -x KimiStatusBar", { stdio: "ignore" }); } catch {}

if (fs.existsSync(configPath)) {
  const lines = fs.readFileSync(configPath, "utf8").split("\n");
  const out = [];
  let i = 0, removed = 0;
  while (i < lines.length) {
    const line = lines[i];
    const headerMatch = line.match(/^\s*\[\[?([^\]]+)\]\]?\s*(#.*)?$/);
    if (headerMatch && headerMatch[1].trim() === "hooks") {
      let j = i + 1;
      const block = [line];
      while (j < lines.length && !/^\s*\[/.test(lines[j])) {
        block.push(lines[j]);
        j++;
      }
      if (block.some((l) => l.includes(MARKER))) {
        while (out.length > 0 && /^\s*#/.test(out[out.length - 1])) {
          out.pop();
        }
        removed += 1;
        i = j;
        continue;
      }
      out.push(...block);
      i = j;
      continue;
    }
    out.push(line);
    i++;
  }
  fs.writeFileSync(configPath, out.join("\n").replace(/\n{3,}/g, "\n\n"));
  console.log(removed > 0
    ? `Removed ${removed} status-bar hook(s) from ${configPath}`
    : `No status-bar hooks found in ${configPath}`);
}

fs.rmSync(sbDir, { recursive: true, force: true });
console.log("Removed", sbDir);

// Only remove the app when this script does NOT run from inside it.
const runningFrom = path.resolve(__dirname, "..", "..", "..");
if (path.resolve(runningFrom) !== path.resolve(APP) && fs.existsSync(APP)) {
  fs.rmSync(APP, { recursive: true, force: true });
  console.log("Removed", APP);
} else if (fs.existsSync(APP)) {
  console.log("App left in place:", APP, "(delete it manually)");
}
