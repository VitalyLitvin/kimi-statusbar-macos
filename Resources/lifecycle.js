#!/usr/bin/env node
// SessionStart/SessionEnd lifecycle: launch the menu bar app when Kimi Code opens
// a session. The app quits ITSELF when it's no longer needed (no active sessions),
// so this script never kills the app.
//
// Active sessions are tracked as one file per session id (read from the hook JSON
// on stdin) under sessions.d/. Distinct files are race-free even when several
// sessions start at once. The app counts the files to know a CLI session is alive.
// Usage: node lifecycle.js <start|end>   (hook JSON, incl. session_id, arrives on stdin)

const fs = require("fs");
const os = require("os");
const path = require("path");
const cp = require("child_process");

const BUNDLE_ID = "com.local.kimistatusbar";
const dir = path.join(process.env.KIMI_CODE_HOME || path.join(os.homedir(), ".kimi-code"), "statusbar");
const sessDir = path.join(dir, "sessions.d");
const event = process.argv[2];

fs.mkdirSync(sessDir, { recursive: true });

const safeId = (s) => String(s || "").replace(/[^A-Za-z0-9_.-]/g, "").slice(0, 64) || "unknown";

let input = "", done = false;
process.stdin.on("data", (d) => (input += d));
process.stdin.on("end", () => run());
process.stdin.on("error", () => run());
setTimeout(run, 1000); // hooks always pipe stdin, but never hang the session

function run() {
  if (done) return; done = true;
  let id = "";
  try { id = JSON.parse(input).session_id; } catch {}
  id = safeId(id);

  if (event === "start") {
    // No mass-clearing of leftover files here: the app ignores session files
    // whose mtime is older than 10 minutes, so stale files are harmless, and
    // clearing them races with other sessions starting at the same moment.
    try { fs.writeFileSync(path.join(sessDir, id), ""); } catch {}
    cp.spawn("open", ["-g", "-b", BUNDLE_ID], { stdio: "ignore", detached: true }).unref();
  } else if (event === "end") {
    try { fs.rmSync(path.join(sessDir, id), { force: true }); } catch {}
  }
  process.exit(0);
}
