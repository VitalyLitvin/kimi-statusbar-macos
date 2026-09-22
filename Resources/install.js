#!/usr/bin/env node
// Kimi Status Bar installer.
//
// Registers the status-bar hooks in ~/.kimi-code/config.toml (idempotent: existing
// status-bar hooks are stripped before re-adding) and copies the hook scripts to
// ~/.kimi-code/statusbar/. Run it from inside the app bundle:
//
//   node "/Applications/KimiStatusBar.app/Contents/Resources/install.js"
//
// or from a git clone:  node Resources/install.js

const fs = require("fs");
const os = require("os");
const path = require("path");
const cp = require("child_process");

const home = os.homedir();
const sbDir = path.join(home, ".kimi-code", "statusbar");
const configPath = path.join(home, ".kimi-code", "config.toml");
const MARKER = sbDir; // every hook command we add points inside this dir
const HEADER = "# --- Kimi Status Bar hooks (managed by install.js) ---";

// process.execPath resolves Homebrew symlinks to the versioned Cellar path, which
// breaks when node is upgraded. Prefer the stable symlink when we detect that case.
function stableNodePath() {
  const exec = process.execPath;
  const m = exec.match(/^(.+\/Cellar\/node\/[^/]+)\/(.*)$/);
  if (m) {
    const prefix = m[1].replace(/\/Cellar\/node\/[^/]+$/, "");
    const link = path.join(prefix, "bin", "node");
    if (fs.existsSync(link)) return link;
  }
  return exec;
}

// Remove every [[hooks]] block whose command points into the statusbar dir, plus
// our header comment. Everything else in the file is left byte-for-byte intact.
function stripHooks(toml) {
  const lines = toml.split("\n");
  const out = [];
  let i = 0;
  while (i < lines.length) {
    const line = lines[i];
    const headerMatch = line.match(/^\s*\[\[?([^\]]+)\]\]?\s*(#.*)?$/);
    if (headerMatch && headerMatch[1].trim() === "hooks") {
      // Collect the whole block: up to (but excluding) the next table header.
      let j = i + 1;
      const block = [line];
      while (j < lines.length && !/^\s*\[/.test(lines[j])) {
        block.push(lines[j]);
        j++;
      }
      if (block.some((l) => l.includes(MARKER))) {
        // Drop contiguous comment lines sitting directly above the block
        // (our header, possibly plus an older hand-written comment group).
        while (out.length > 0 && /^\s*#/.test(out[out.length - 1])) {
          out.pop();
        }
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
  // Collapse 3+ consecutive blank lines left behind by stripping.
  return out.join("\n").replace(/\n{3,}/g, "\n\n");
}

function hookBlock(node) {
  const cmd = (script, arg) => `${node} ${path.join(sbDir, script)} ${arg}`;
  const hooks = [
    // State hooks (drive the icon/label)
    ["UserPromptSubmit", cmd("update.js", "prompt")],
    ["PreToolUse", cmd("update.js", "pre")],
    ["PostToolUse", cmd("update.js", "post")],
    ["PermissionRequest", cmd("update.js", "permission")],
    ["PermissionResult", cmd("update.js", "permission_result")],
    ["Stop", cmd("update.js", "stop")],
    ["Interrupt", cmd("update.js", "interrupt")],
    // Lifecycle hooks (the app quits itself once no sessions remain)
    ["SessionStart", cmd("lifecycle.js", "start")],
    ["SessionEnd", cmd("lifecycle.js", "end")],
  ];
  return (
    HEADER +
    "\n" +
    hooks
      .map(
        ([event, command]) =>
          `[[hooks]]\nevent = "${event}"\ncommand = "${command}"\ntimeout = 5\n`
      )
      .join("\n")
  );
}

function main() {
  const node = stableNodePath();

  fs.mkdirSync(sbDir, { recursive: true });
  for (const f of ["update.js", "lifecycle.js"]) {
    fs.copyFileSync(path.join(__dirname, f), path.join(sbDir, f));
  }

  let toml = "";
  if (fs.existsSync(configPath)) {
    toml = fs.readFileSync(configPath, "utf8");
    const bak = configPath + ".bak-statusbar";
    if (!fs.existsSync(bak)) fs.copyFileSync(configPath, bak);
  }
  toml = stripHooks(toml);
  if (toml.length > 0 && !toml.endsWith("\n")) toml += "\n";
  if (toml.trim().length > 0) toml += "\n";
  toml += hookBlock(node) + "\n";
  fs.writeFileSync(configPath, toml);

  // Best-effort: make sure the app is in /Applications so `open -b` finds it.
  const appBundle = path.resolve(__dirname, "..", "..", "..");
  const installed = "/Applications/KimiStatusBar.app";
  if (appBundle.endsWith(".app") && path.resolve(appBundle) !== path.resolve(installed)) {
    if (!fs.existsSync(installed)) {
      try {
        cp.execSync(`cp -R ${JSON.stringify(appBundle)} ${JSON.stringify(installed)}`);
        console.log("Installed app to", installed);
      } catch {
        console.log("NOTE: could not copy the app to /Applications — drag it there yourself.");
      }
    }
  }

  console.log("Kimi Status Bar hooks installed into", configPath);
  console.log("Scripts:", path.join(sbDir, "update.js"), "and", path.join(sbDir, "lifecycle.js"));
  console.log("Backup (first run only):", configPath + ".bak-statusbar");
  console.log("");
  console.log("Already-running Kimi Code sessions pick the hooks up on their next start.");
}

try {
  main();
} catch (e) {
  console.error("install failed:", e.message);
  process.exit(1);
}
