#!/usr/bin/env node

import { createHash } from "node:crypto";
import { execFileSync } from "node:child_process";
import { existsSync, lstatSync, mkdirSync, readFileSync, readdirSync, renameSync, rmSync, statSync, writeFileSync } from "node:fs";
import { homedir } from "node:os";
import { dirname, join, relative, resolve } from "node:path";
import { fileURLToPath } from "node:url";

const SCRIPT_DIR = dirname(fileURLToPath(import.meta.url));
const PLUGIN_ROOT = resolve(SCRIPT_DIR, "..");
const SHIPPED_POLICY_PATH = join(PLUGIN_ROOT, "references", "model-policy.json");
const STATE_SCRIPT = join(SCRIPT_DIR, "df-state.sh");
const HARNESSES = ["claude", "codex"];
const REQUIRED_RESPONSIBILITIES = [
  "session_router",
  "orchestrator",
  "menial_scoped_investigation",
  "implementation_delegate",
  "judgment_delegate",
  "investigation_synthesizer",
  "design_runners",
  "discovery_reviewers",
  "recheck_leaf_reviewers",
  "eval_graders",
  "persona_reviewers_cli",
  "cross_model_review",
  "discovery_context",
  "escalation"
];
const KNOWN_TARGET_KINDS = ["session", "named-agent", "native-model", "cli", "transport", "parallel"];
const NATIVE_MODELS = ["sonnet", "opus"];
const TRANSPORTS = ["codex-cli", "claude-tmux"];
const PLAN_SCHEMA_VERSION = 1;
const LOCK_WAIT_MS = 10_000;
const STALE_LOCK_MS = 30_000;

class RolePolicyError extends Error {}

function fail(message) {
  throw new RolePolicyError(`df-role: ${message}`);
}

function configFail(sourcePath, field, message) {
  fail(`${sourcePath}: ${field}: ${message}`);
}

function stable(value) {
  if (Array.isArray(value)) return value.map(stable);
  if (value && typeof value === "object") {
    return Object.fromEntries(Object.keys(value).sort().map((key) => [key, stable(value[key])]));
  }
  return value;
}

function stableJson(value) {
  return JSON.stringify(stable(value));
}

function sha256(value) {
  return createHash("sha256").update(stableJson(value)).digest("hex");
}

function isObject(value) {
  return value !== null && typeof value === "object" && !Array.isArray(value);
}

function own(object, key) {
  return Object.prototype.hasOwnProperty.call(object, key);
}

function assertKeys(value, allowed, sourcePath, field) {
  for (const key of Object.keys(value)) {
    if (!allowed.includes(key)) configFail(sourcePath, `${field}.${key}`, "unknown field");
  }
}

function requireString(value, sourcePath, field) {
  if (typeof value !== "string" || value.length === 0) {
    configFail(sourcePath, field, "must be a non-empty string");
  }
  return value;
}

function requireArray(value, sourcePath, field) {
  if (!Array.isArray(value)) configFail(sourcePath, field, "must be an array");
  return value;
}

function parseJsonFile(sourcePath, label) {
  let input;
  try {
    input = readFileSync(sourcePath, "utf8");
  } catch {
    fail(`${label} is unreadable: ${sourcePath}`);
  }
  try {
    return JSON.parse(input);
  } catch {
    configFail(sourcePath, "$", "must contain valid JSON");
  }
}

function validateTarget(target, sourcePath, field, allowParallel = true) {
  if (!isObject(target)) configFail(sourcePath, field, "must be an object");
  const kind = requireString(target.kind, sourcePath, `${field}.kind`);
  if (!KNOWN_TARGET_KINDS.includes(kind)) {
    configFail(sourcePath, `${field}.kind`, "is not a supported target kind");
  }
  if (kind === "session") {
    assertKeys(target, ["kind"], sourcePath, field);
    return;
  }
  if (kind === "named-agent") {
    assertKeys(target, ["kind", "agent"], sourcePath, field);
    const agent = requireString(target.agent, sourcePath, `${field}.agent`);
    if (!/^[A-Za-z0-9_-]+$/.test(agent)) {
      configFail(sourcePath, `${field}.agent`, "must contain only letters, numbers, underscores, or hyphens");
    }
    return;
  }
  if (kind === "native-model") {
    assertKeys(target, ["kind", "model"], sourcePath, field);
    const model = requireString(target.model, sourcePath, `${field}.model`);
    if (!NATIVE_MODELS.includes(model)) {
      configFail(sourcePath, `${field}.model`, "is not a shipped native model");
    }
    return;
  }
  if (kind === "cli") {
    assertKeys(target, ["kind", "model", "effort"], sourcePath, field);
    if (target.model !== null || target.effort !== null) {
      configFail(sourcePath, field, "CLI targets must leave model and effort null");
    }
    return;
  }
  if (kind === "transport") {
    assertKeys(target, ["kind", "name"], sourcePath, field);
    const name = requireString(target.name, sourcePath, `${field}.name`);
    if (!TRANSPORTS.includes(name)) configFail(sourcePath, `${field}.name`, "is not a shipped transport");
    return;
  }
  if (!allowParallel) configFail(sourcePath, field, "parallel targets cannot be nested");
  assertKeys(target, ["kind", "targets"], sourcePath, field);
  const targets = requireArray(target.targets, sourcePath, `${field}.targets`);
  if (targets.length === 0) configFail(sourcePath, `${field}.targets`, "must not be empty");
  targets.forEach((leaf, index) => validateTarget(leaf, sourcePath, `${field}.targets.${index}`, false));
}

function validateRoleMap(roleMap, policy, sourcePath, field, complete) {
  if (!isObject(roleMap)) configFail(sourcePath, field, "must be an object");
  assertKeys(roleMap, HARNESSES, sourcePath, field);
  for (const harness of HARNESSES) {
    const harnessField = `${field}.${harness}`;
    if (!own(roleMap, harness)) {
      if (complete) configFail(sourcePath, harnessField, "missing required harness mapping");
      continue;
    }
    if (!isObject(roleMap[harness])) configFail(sourcePath, harnessField, "must be an object");
    assertKeys(roleMap[harness], policy.responsibilities, sourcePath, harnessField);
    for (const responsibility of policy.responsibilities) {
      const responsibilityField = `${harnessField}.${responsibility}`;
      if (!own(roleMap[harness], responsibility)) {
        if (complete) configFail(sourcePath, responsibilityField, "missing required responsibility mapping");
        continue;
      }
      const laneMap = roleMap[harness][responsibility];
      if (!isObject(laneMap)) configFail(sourcePath, responsibilityField, "must be an object");
      assertKeys(laneMap, policy.lanes, sourcePath, responsibilityField);
      for (const lane of policy.lanes) {
        const laneField = `${responsibilityField}.${lane}`;
        if (!own(laneMap, lane)) {
          if (complete) configFail(sourcePath, laneField, "missing required lane mapping");
          continue;
        }
        validateTarget(laneMap[lane], sourcePath, laneField);
      }
    }
  }
}

export function validatePolicy(policy, sourcePath = SHIPPED_POLICY_PATH) {
  if (!isObject(policy)) configFail(sourcePath, "$", "must be an object");
  const rootKeys = ["schemaVersion", "responsibilities", "lanes", "overridePrecedence", "allowedProjectKeys", "roles"];
  assertKeys(policy, rootKeys, sourcePath, "$");
  for (const key of rootKeys) {
    if (!own(policy, key)) configFail(sourcePath, key, "is required");
  }
  if (policy.schemaVersion !== PLAN_SCHEMA_VERSION) configFail(sourcePath, "schemaVersion", "must be 1");
  const responsibilities = requireArray(policy.responsibilities, sourcePath, "responsibilities");
  if (responsibilities.length === 0) configFail(sourcePath, "responsibilities", "must not be empty");
  for (const responsibility of responsibilities) requireString(responsibility, sourcePath, "responsibilities");
  if (new Set(responsibilities).size !== responsibilities.length) configFail(sourcePath, "responsibilities", "must not contain duplicates");
  if (stableJson(responsibilities) !== stableJson(REQUIRED_RESPONSIBILITIES)) {
    configFail(sourcePath, "responsibilities", "must declare every supported responsibility in the shipped order");
  }
  const lanes = requireArray(policy.lanes, sourcePath, "lanes");
  if (stableJson(lanes) !== stableJson(["quick", "standard", "high-consequence"])) {
    configFail(sourcePath, "lanes", "must declare quick, standard, and high-consequence in that order");
  }
  if (stableJson(policy.overridePrecedence) !== stableJson(["shipped", "machine", "project"])) {
    configFail(sourcePath, "overridePrecedence", "must be shipped, machine, project");
  }
  if (stableJson(policy.allowedProjectKeys) !== stableJson(["schemaVersion", "roles"])) {
    configFail(sourcePath, "allowedProjectKeys", "must be schemaVersion and roles");
  }
  validateRoleMap(policy.roles, policy, sourcePath, "roles", true);
  return policy;
}

function validateOverride(override, policy, sourcePath) {
  if (!isObject(override)) configFail(sourcePath, "$", "must be an object");
  assertKeys(override, policy.allowedProjectKeys, sourcePath, "$");
  for (const key of policy.allowedProjectKeys) {
    if (!own(override, key)) configFail(sourcePath, key, "is required");
  }
  if (override.schemaVersion !== PLAN_SCHEMA_VERSION) configFail(sourcePath, "schemaVersion", "must be 1");
  validateRoleMap(override.roles, policy, sourcePath, "roles", false);
  return override;
}

function readPolicy() {
  const policyPath = resolve(process.env.DF_ROLE_POLICY_PATH || SHIPPED_POLICY_PATH);
  return { path: policyPath, value: validatePolicy(parseJsonFile(policyPath, "policy"), policyPath) };
}

function readOptionalOverride(sourcePath, policy) {
  if (!existsSync(sourcePath)) return null;
  return { path: sourcePath, value: validateOverride(parseJsonFile(sourcePath, "override"), policy, sourcePath) };
}

function machineConfigPath() {
  const configRoot = process.env.XDG_CONFIG_HOME || join(homedir(), ".config");
  return join(configRoot, "dark-factory", "config.json");
}

function targetAt(override, harness, responsibility, lane) {
  return override?.value.roles?.[harness]?.[responsibility]?.[lane];
}

function buildResolutions(policyLayer, machineLayer, projectLayer, harness) {
  const resolutions = [];
  for (const responsibility of policyLayer.value.responsibilities) {
    for (const lane of policyLayer.value.lanes) {
      let target = policyLayer.value.roles[harness][responsibility][lane];
      const provenance = [{ kind: "shipped", path: policyLayer.path }];
      for (const [kind, layer] of [["machine", machineLayer], ["project", projectLayer]]) {
        const override = targetAt(layer, harness, responsibility, lane);
        if (override) {
          target = override;
          provenance.push({ kind, path: layer.path });
        }
      }
      resolutions.push({ harness, responsibility, lane, target: stable(target), provenance });
    }
  }
  return resolutions;
}

function assertRunId(runId) {
  if (typeof runId !== "string" || !/^[A-Za-z0-9._-]+$/.test(runId)) {
    fail("run must match [A-Za-z0-9._-]+ and cannot traverse a path");
  }
}

function canonicalRepoRoot(input) {
  const requested = resolve(input);
  let stat;
  try {
    stat = statSync(requested);
  } catch {
    fail(`repo root does not exist: ${requested}`);
  }
  if (!stat.isDirectory()) fail(`repo root is not a directory: ${requested}`);
  let gitRoot;
  try {
    gitRoot = execFileSync("git", ["-C", requested, "rev-parse", "--show-toplevel"], { encoding: "utf8" }).trim();
  } catch {
    fail(`repo root is not a Git worktree: ${requested}`);
  }
  if (resolve(gitRoot) !== requested) fail(`repo root must be the Git worktree root: ${requested}`);
  return requested;
}

function statePathFor(repoRoot, runId) {
  assertRunId(runId);
  let output;
  try {
    output = execFileSync("bash", [STATE_SCRIPT, "path", runId], { cwd: repoRoot, encoding: "utf8" }).trim();
  } catch {
    fail(`could not locate external run state for ${runId}`);
  }
  const statePath = resolve(output);
  const rootPath = resolve(execFileSync("bash", [STATE_SCRIPT, "path"], { cwd: repoRoot, encoding: "utf8" }).trim());
  if (relative(rootPath, statePath).startsWith("..")) fail("external run path escapes its state root");
  return statePath;
}

function validateRunState(runDir, runId, repoRoot) {
  const runFile = join(runDir, "run.tsv");
  const dispatchFile = join(runDir, "dispatches.tsv");
  if (!existsSync(runFile) || !existsSync(dispatchFile)) fail(`external run ${runId} is missing required state files`);
  const rows = readFileSync(runFile, "utf8").trimEnd().split("\n");
  const expectedHeader = "run_id\tlane\tcreated\tfinish_predicate\tartifact_sha\tbudget_dispatches\tbudget_wall_minutes\tstate";
  if (rows.length !== 2 || rows[0] !== expectedHeader) fail(`external run ${runId} has malformed run.tsv`);
  const row = rows[1].split("\t");
  if (row.length !== 8 || row[0] !== runId || !["quick", "standard", "high-consequence"].includes(row[1]) || !/^[1-9][0-9]*$/.test(row[5]) || !/^[1-9][0-9]*$/.test(row[6]) || !["running", "paused", "done", "stopped-budget", "stopped-operator"].includes(row[7])) {
    fail(`external run ${runId} has malformed run state`);
  }
  const dispatchRows = readFileSync(dispatchFile, "utf8").trimEnd().split("\n");
  if (dispatchRows[0] !== "seq\tts\trole\tpurpose\tparent_seq\toutcome" || dispatchRows.some((line, index) => index > 0 && line.split("\t").length !== 6)) {
    fail(`external run ${runId} has malformed dispatch state`);
  }
  if (row[4] !== "-") {
    try {
      execFileSync("git", ["-C", repoRoot, "cat-file", "-e", `${row[4]}^{commit}`], { stdio: "ignore" });
    } catch {
      fail(`external run ${runId} belongs to a different repository`);
    }
  }
}

function planPathFor(runDir) {
  return join(runDir, "work", "role-plan.json");
}

function validatePlanTarget(target, field) {
  validateTarget(target, "role plan", field);
}

function validateFrozenPlan(plan, runId, repoRoot) {
  if (!isObject(plan)) fail("role plan must be an object");
  const keys = ["schemaVersion", "runId", "repoRoot", "harness", "responsibilities", "lanes", "policyDigest", "resolutions", "planDigest"];
  for (const key of keys) if (!own(plan, key)) fail(`role plan is missing ${key}`);
  if (plan.schemaVersion !== PLAN_SCHEMA_VERSION || plan.runId !== runId || plan.repoRoot !== repoRoot || !HARNESSES.includes(plan.harness)) {
    fail("role plan does not match the requested run, repository, or harness");
  }
  if (!Array.isArray(plan.responsibilities) || !Array.isArray(plan.lanes) || !Array.isArray(plan.resolutions)) fail("role plan has malformed matrix fields");
  if (stableJson(plan.lanes) !== stableJson(["quick", "standard", "high-consequence"]) || plan.responsibilities.length === 0) {
    fail("role plan has an invalid responsibility-by-lane matrix");
  }
  const expectedRows = plan.responsibilities.length * plan.lanes.length;
  if (plan.resolutions.length !== expectedRows) fail("role plan has an incomplete responsibility-by-lane matrix");
  const seen = new Set();
  for (const resolution of plan.resolutions) {
    if (!isObject(resolution) || resolution.harness !== plan.harness || !plan.responsibilities.includes(resolution.responsibility) || !plan.lanes.includes(resolution.lane) || !Array.isArray(resolution.provenance) || resolution.provenance.length === 0) {
      fail("role plan has a malformed resolution");
    }
    const matrixKey = `${resolution.responsibility}\u0000${resolution.lane}`;
    if (seen.has(matrixKey)) fail("role plan has duplicate responsibility-by-lane rows");
    seen.add(matrixKey);
    validatePlanTarget(resolution.target, `resolutions.${resolution.responsibility}.${resolution.lane}.target`);
    for (const source of resolution.provenance) {
      if (!isObject(source) || !["shipped", "machine", "project"].includes(source.kind) || typeof source.path !== "string" || source.path.length === 0) {
        fail("role plan has malformed provenance");
      }
    }
  }
  if (typeof plan.policyDigest !== "string" || !/^[a-f0-9]{64}$/.test(plan.policyDigest) || typeof plan.planDigest !== "string" || !/^[a-f0-9]{64}$/.test(plan.planDigest)) {
    fail("role plan has an invalid digest");
  }
  const withoutPlanDigest = { ...plan };
  delete withoutPlanDigest.planDigest;
  if (sha256(withoutPlanDigest) !== plan.planDigest) fail("role plan digest does not match its contents");
  const policyDigest = sha256(plan.resolutions);
  if (policyDigest !== plan.policyDigest) fail("role plan policy digest does not match its resolutions");
  return plan;
}

function readFrozenPlan(runDir, runId, repoRoot) {
  const planPath = planPathFor(runDir);
  if (!existsSync(planPath)) return null;
  let plan;
  try {
    plan = JSON.parse(readFileSync(planPath, "utf8"));
  } catch {
    fail(`role plan is malformed: ${planPath}`);
  }
  return validateFrozenPlan(plan, runId, repoRoot);
}

function sleep(milliseconds) {
  return new Promise((resolveSleep) => setTimeout(resolveSleep, milliseconds));
}

async function acquirePlanLock(runDir) {
  const lockPath = join(runDir, "work", "role-plan.lock");
  const deadline = Date.now() + LOCK_WAIT_MS;
  mkdirSync(dirname(lockPath), { recursive: true });
  while (Date.now() < deadline) {
    try {
      mkdirSync(lockPath);
      writeFileSync(join(lockPath, "owner"), `${process.pid}\n`, { mode: 0o600 });
      return lockPath;
    } catch (error) {
      if (error?.code !== "EEXIST") throw error;
      let lockStat;
      try {
        lockStat = lstatSync(lockPath);
      } catch {
        continue;
      }
      if (Date.now() - lockStat.mtimeMs > STALE_LOCK_MS) {
        const stalePath = `${lockPath}.stale.${process.pid}`;
        try {
          renameSync(lockPath, stalePath);
          rmSync(stalePath, { recursive: true, force: true });
        } catch {
          // Another contender reclaimed the stale lock first.
        }
      }
      await sleep(25);
    }
  }
  fail(`could not acquire the role-plan lock for ${runDir}`);
}

function releasePlanLock(lockPath) {
  rmSync(lockPath, { recursive: true, force: true });
}

function writePlanAtomically(planPath, plan) {
  const tempPath = `${planPath}.tmp.${process.pid}.${Date.now()}`;
  writeFileSync(tempPath, `${stableJson(plan)}\n`, { mode: 0o600 });
  renameSync(tempPath, planPath);
}

function parseArgs(argv) {
  const [command, ...rest] = argv;
  if (!command || !["prepare-run", "resolve", "preflight"].includes(command)) {
    fail("usage: df-role.mjs prepare-run|resolve|preflight --run <id> [options]");
  }
  const options = {};
  for (let index = 0; index < rest.length; index += 2) {
    const flag = rest[index];
    const value = rest[index + 1];
    if (!flag?.startsWith("--") || value === undefined) fail("options must be supplied as --name value pairs");
    const key = flag.slice(2);
    if (!["run", "harness", "repo-root", "responsibility", "lane"].includes(key) || own(options, key)) {
      fail(`unknown or repeated option ${flag}`);
    }
    options[key] = value;
  }
  if (!options.run) fail("--run is required");
  return { command, options };
}

function requireOption(options, name) {
  if (!options[name]) fail(`--${name} is required`);
  return options[name];
}

function findResolution(plan, responsibility, lane) {
  if (!plan.responsibilities.includes(responsibility)) fail(`unknown responsibility ${responsibility}`);
  if (!plan.lanes.includes(lane)) fail(`unknown lane ${lane}`);
  const resolution = plan.resolutions.find((row) => row.responsibility === responsibility && row.lane === lane);
  if (!resolution) fail(`role plan is missing ${responsibility} for ${lane}`);
  return resolution;
}

function namedAgents(target, names = []) {
  if (target.kind === "named-agent") names.push(target.agent);
  if (target.kind === "parallel") target.targets.forEach((leaf) => namedAgents(leaf, names));
  return names;
}

function uniqueExistingDirectories(paths) {
  const directories = [];
  const seen = new Set();
  for (const candidate of paths.filter(Boolean)) {
    try {
      if (!statSync(candidate).isDirectory()) continue;
      const canonical = resolve(candidate);
      if (!seen.has(canonical)) {
        seen.add(canonical);
        directories.push(canonical);
      }
    } catch {
      // An optional local agent directory need not exist.
    }
  }
  return directories;
}

function agentDirectories(harness) {
  if (harness === "claude") {
    const configured = [process.env.DF_CLAUDE_AGENTS_DIR, process.env.CLAUDE_AGENTS_DIR].filter(Boolean);
    if (configured.length > 0) return uniqueExistingDirectories(configured);
    return uniqueExistingDirectories([
      join(PLUGIN_ROOT, "agents"),
      join(process.env.CLAUDE_CONFIG_DIR || join(homedir(), ".claude"), "agents")
    ]);
  }
  const configured = [process.env.DF_CODEX_AGENTS_DIR, process.env.CODEX_AGENTS_DIR].filter(Boolean);
  if (configured.length > 0) return uniqueExistingDirectories(configured);
  return uniqueExistingDirectories([join(process.env.CODEX_HOME || join(homedir(), ".codex"), "agents")]);
}

function definitionNames(harness, content) {
  const match = harness === "claude"
    ? /^name:\s*['"]?([^'"\n]+?)['"]?\s*$/m.exec(content)
    : /^name\s*=\s*['"]([^'"]+)['"]\s*$/m.exec(content);
  return match ? [match[1].trim()] : [];
}

export function validateNamedAgents(harness, target) {
  const wanted = [...new Set(namedAgents(target))];
  const directories = agentDirectories(harness);
  for (const agent of wanted) {
    const definitions = [];
    for (const directory of directories) {
      for (const entry of readdirSync(directory, { withFileTypes: true })) {
        if (!entry.isFile()) continue;
        const extension = harness === "claude" ? ".md" : ".toml";
        if (!entry.name.endsWith(extension)) continue;
        const definitionPath = join(directory, entry.name);
        let content;
        try {
          content = readFileSync(definitionPath, "utf8");
        } catch {
          continue;
        }
        if (definitionNames(harness, content).includes(agent)) definitions.push(definitionPath);
      }
    }
    if (definitions.length === 0) fail(`named agent ${agent} is missing for harness ${harness}`);
    if (definitions.length > 1) fail(`named agent ${agent} is ambiguous for harness ${harness}`);
  }
  return wanted;
}

export async function prepareRunRolePlan({ runId, harness, repoRoot }) {
  assertRunId(runId);
  if (!HARNESSES.includes(harness)) fail(`unknown harness ${harness}`);
  const canonicalRoot = canonicalRepoRoot(repoRoot);
  const runDir = statePathFor(canonicalRoot, runId);
  validateRunState(runDir, runId, canonicalRoot);
  const existing = readFrozenPlan(runDir, runId, canonicalRoot);
  if (existing) {
    if (existing.harness !== harness) fail(`role plan for ${runId} is already frozen for harness ${existing.harness}`);
    return existing;
  }
  const lockPath = await acquirePlanLock(runDir);
  try {
    const winner = readFrozenPlan(runDir, runId, canonicalRoot);
    if (winner) {
      if (winner.harness !== harness) fail(`role plan for ${runId} is already frozen for harness ${winner.harness}`);
      return winner;
    }
    const policyLayer = readPolicy();
    const machineLayer = readOptionalOverride(machineConfigPath(), policyLayer.value);
    const projectLayer = readOptionalOverride(join(canonicalRoot, ".agents", "dark-factory.json"), policyLayer.value);
    const resolutions = buildResolutions(policyLayer, machineLayer, projectLayer, harness);
    const withoutPlanDigest = {
      schemaVersion: PLAN_SCHEMA_VERSION,
      runId,
      repoRoot: canonicalRoot,
      harness,
      responsibilities: policyLayer.value.responsibilities,
      lanes: policyLayer.value.lanes,
      policyDigest: sha256(resolutions),
      resolutions
    };
    const plan = { ...withoutPlanDigest, planDigest: sha256(withoutPlanDigest) };
    validateFrozenPlan(plan, runId, canonicalRoot);
    writePlanAtomically(planPathFor(runDir), plan);
    return plan;
  } finally {
    releasePlanLock(lockPath);
  }
}

export function resolveFrozenRole({ runId, responsibility, lane, repoRoot = process.cwd() }) {
  assertRunId(runId);
  const canonicalRoot = canonicalRepoRoot(repoRoot);
  const runDir = statePathFor(canonicalRoot, runId);
  validateRunState(runDir, runId, canonicalRoot);
  const plan = readFrozenPlan(runDir, runId, canonicalRoot);
  if (!plan) fail(`role plan has not been prepared for ${runId}`);
  return findResolution(plan, responsibility, lane);
}

export function preflightFrozenRole({ runId, responsibility, lane, repoRoot = process.cwd() }) {
  const resolution = resolveFrozenRole({ runId, responsibility, lane, repoRoot });
  const agents = validateNamedAgents(resolution.harness, resolution.target);
  return { ...resolution, validatedNamedAgents: agents };
}

async function main() {
  const { command, options } = parseArgs(process.argv.slice(2));
  const runId = requireOption(options, "run");
  const repoRoot = options["repo-root"] || process.cwd();
  let result;
  if (command === "prepare-run") {
    result = await prepareRunRolePlan({
      runId,
      harness: requireOption(options, "harness"),
      repoRoot: requireOption(options, "repo-root")
    });
  } else if (command === "resolve") {
    result = resolveFrozenRole({
      runId,
      responsibility: requireOption(options, "responsibility"),
      lane: requireOption(options, "lane"),
      repoRoot
    });
  } else {
    result = preflightFrozenRole({
      runId,
      responsibility: requireOption(options, "responsibility"),
      lane: requireOption(options, "lane"),
      repoRoot
    });
  }
  process.stdout.write(`${stableJson(result)}\n`);
}

if (process.argv[1] === fileURLToPath(import.meta.url)) {
  main().catch((error) => {
    process.stderr.write(`${error instanceof Error ? error.message : String(error)}\n`);
    process.exitCode = 1;
  });
}
