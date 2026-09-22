#!/usr/bin/env node
// Invoked by Kimi Code hooks (see [[hooks]] in ~/.kimi-code/config.toml). Reads the
// hook JSON payload on stdin, maps the event to a status, and atomically writes
// ~/.kimi-code/statusbar/state.json. Prints nothing: stdout of blockable events
// (UserPromptSubmit/PreToolUse/Stop) is appended to the model context.
// Usage: node update.js <prompt|pre|post|permission|permission_result|stop|interrupt>

const fs = require("fs");
const os = require("os");
const path = require("path");
const cp = require("child_process");

const dir = path.join(os.homedir(), ".kimi-code", "statusbar");
const statePath = path.join(dir, "state.json");
const event = process.argv[2] || "";

const TOOL_LABELS = {
  Bash: "Running command", Edit: "Editing", Write: "Writing",
  Read: "Reading", Grep: "Searching", Glob: "Searching",
  WebSearch: "Searching web", FetchURL: "Browsing web",
  Agent: "Delegating", AgentSwarm: "Delegating", TodoList: "Planning",
  Skill: "Using skill", CronCreate: "Scheduling", CronDelete: "Scheduling",
  CronList: "Scheduling", TaskOutput: "Checking task", WaitFor: "Waiting for task",
};

let raw = "";
process.stdin.on("data", (d) => (raw += d));
process.stdin.on("end", () => {
  let p = {};
  try { p = JSON.parse(raw || "{}"); } catch {}

  // Optional debug log of every hook invocation. Off by default; enable with
  // KIMI_STATUSBAR_DEBUG=1 to inspect what fires.
  if (process.env.KIMI_STATUSBAR_DEBUG === "1") {
    try {
      fs.mkdirSync(dir, { recursive: true });
      fs.appendFileSync(path.join(dir, "hooks.log"),
        `${new Date().toISOString()} [${event}] tool=${p.tool_name || "-"} title=${JSON.stringify(p.session_title || "")} keys=${Object.keys(p).join(",")}\n`);
    } catch {}
  }

  // Register this session as active so the app counts it, even for a session that
  // started before the hooks were installed (it never fired its one-time
  // SessionStart). Touching the file here keeps the app alive while the session
  // works; SessionEnd removes it. The file is also the app's liveness signal:
  // it counts only files touched within the last few minutes, and any event
  // here relaunches the app if it has quit in the meantime.
  const sid = String(p.session_id || "").replace(/[^A-Za-z0-9_.-]/g, "").slice(0, 64);
  if (sid) {
    try {
      const sessDir = path.join(dir, "sessions.d");
      fs.mkdirSync(sessDir, { recursive: true });
      fs.writeFileSync(path.join(sessDir, sid), "");
    } catch {}
    try {
      cp.execSync("pgrep -x KimiStatusBar", { stdio: "ignore" });
    } catch {
      cp.spawn("open", ["-g", "-b", "com.local.kimistatusbar"], { stdio: "ignore", detached: true }).unref();
    }
  }

  let prev = {};
  try { prev = JSON.parse(fs.readFileSync(statePath, "utf8")); } catch {}

  const project = p.cwd ? path.basename(p.cwd) : prev.project || "";
  const title = p.session_title || prev.title || "";
  const ts = Math.floor(Date.now() / 1000);
  let state = "idle", label = "", startedAt = prev.startedAt || 0;

  switch (event) {
    case "prompt":
      state = "thinking"; label = "Thinking…"; startedAt = ts; break;
    case "pre": {
      const t = p.tool_name || "";
      // Known tools get a friendly verb; everything else (incl. long
      // mcp__server__method names) collapses to a generic "Using tool".
      state = "tool"; label = TOOL_LABELS[t] || "Using tool";
      if (!startedAt) startedAt = ts;
      break;
    }
    case "post":
      state = "thinking"; label = "Thinking…";
      if (!startedAt) startedAt = ts;
      break;
    case "permission":
      state = "permission"; label = "Awaiting permission";
      startedAt = 0;
      break;
    case "permission_result":
      state = "thinking"; label = "Thinking…";
      if (!startedAt) startedAt = ts;
      break;
    case "stop":
      state = "done"; label = "Done"; startedAt = 0; break;
    case "interrupt":
      state = "waiting"; label = "Interrupted"; startedAt = 0; break;
    default:
      return;
  }

  const out = { state, label, tool: p.tool_name || "", project, title, sessionId: p.session_id || "", startedAt, ts };
  try {
    fs.mkdirSync(dir, { recursive: true });
    const tmp = statePath + "." + process.pid + ".tmp";
    fs.writeFileSync(tmp, JSON.stringify(out));
    fs.renameSync(tmp, statePath);
  } catch {}
});
