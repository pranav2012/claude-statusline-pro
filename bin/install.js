#!/usr/bin/env node
"use strict";

const fs = require("fs");
const os = require("os");
const path = require("path");

const C = {
  reset: "\x1b[0m",
  bold: "\x1b[1m",
  green: "\x1b[32m",
  yellow: "\x1b[33m",
  red: "\x1b[31m",
  cyan: "\x1b[36m",
  dim: "\x1b[2m",
};

function log(msg) {
  process.stdout.write(msg + "\n");
}

function die(msg) {
  process.stderr.write(`${C.red}✖ ${msg}${C.reset}\n`);
  process.exit(1);
}

const configDir = process.env.CLAUDE_CONFIG_DIR || path.join(os.homedir(), ".claude");
const scriptName = "statusline-command.sh";
const srcScript = path.join(__dirname, "..", scriptName);
const destScript = path.join(configDir, scriptName);
const settingsPath = path.join(configDir, "settings.json");

log(`${C.bold}${C.cyan}claude-statusline-pro${C.reset} ${C.dim}installer${C.reset}\n`);

if (!fs.existsSync(srcScript)) {
  die(`Bundled ${scriptName} not found at ${srcScript}`);
}

// Ensure config dir exists.
fs.mkdirSync(configDir, { recursive: true });

// Copy the statusline script and make it executable.
fs.copyFileSync(srcScript, destScript);
fs.chmodSync(destScript, 0o755);
log(`${C.green}✔${C.reset} Installed script  ${C.dim}${destScript}${C.reset}`);

// Read or initialize settings.json.
let settings = {};
let raw = "";
if (fs.existsSync(settingsPath)) {
  raw = fs.readFileSync(settingsPath, "utf8");
  try {
    settings = raw.trim() ? JSON.parse(raw) : {};
  } catch (e) {
    die(
      `Could not parse ${settingsPath} as JSON (${e.message}).\n` +
        `  Fix or remove it, then re-run. Your file was left untouched.`
    );
  }
}

const desired = {
  type: "command",
  command: `bash ${destScript}`,
};

const current = settings.statusLine;
const alreadySet =
  current &&
  current.type === desired.type &&
  current.command === desired.command;

if (alreadySet) {
  log(`${C.green}✔${C.reset} settings.json already configured — nothing to change`);
} else {
  // Back up any existing settings file before modifying.
  if (raw) {
    const backup = `${settingsPath}.bak`;
    fs.writeFileSync(backup, raw);
    log(`${C.green}✔${C.reset} Backed up settings  ${C.dim}${backup}${C.reset}`);
  }
  settings.statusLine = desired;
  fs.writeFileSync(settingsPath, JSON.stringify(settings, null, 2) + "\n");
  log(`${C.green}✔${C.reset} Wired up statusLine  ${C.dim}${settingsPath}${C.reset}`);
}

// Warn about runtime dependencies the script relies on.
const { execSync } = require("child_process");
const deps = ["jq", "python3", "curl"];
const missing = deps.filter((bin) => {
  try {
    execSync(`command -v ${bin}`, { stdio: "ignore" });
    return false;
  } catch {
    return true;
  }
});
if (missing.length) {
  log(
    `\n${C.yellow}⚠ Missing dependencies: ${missing.join(", ")}${C.reset}\n` +
      `  ${C.dim}Install them so usage/cost sections render. On macOS: brew install ${missing.join(" ")}${C.reset}`
  );
}

log(
  `\n${C.green}${C.bold}Done.${C.reset} Start a new Claude Code session (or run ${C.cyan}/statusline${C.reset}) to see it.`
);
