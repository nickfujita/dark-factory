#!/usr/bin/env node

import { readFileSync, readdirSync } from "node:fs";
import { join, resolve } from "node:path";
import { fileURLToPath } from "node:url";
import { validateNamedAgents, validatePolicy } from "./df-role.mjs";

const SCRIPT_DIR = resolve(fileURLToPath(new URL(".", import.meta.url)));
const PLUGIN_ROOT = resolve(SCRIPT_DIR, "..");
const DEFAULT_POLICY = join(PLUGIN_ROOT, "references", "model-policy.json");
const SKILL_TREES = [join(PLUGIN_ROOT, "skills"), join(PLUGIN_ROOT, "codex-plugin", "skills")];

function fail(message) {
  throw new Error(`check-model-policy: ${message}`);
}

function parseArgs(argv) {
  const options = { policy: DEFAULT_POLICY, validateAgents: false };
  for (let index = 0; index < argv.length; index += 1) {
    const flag = argv[index];
    if (flag === "--policy") {
      if (!argv[index + 1]) fail("--policy requires a path");
      options.policy = resolve(argv[index + 1]);
      index += 1;
    } else if (flag === "--validate-agents") {
      options.validateAgents = true;
    } else if (flag === "--skip-agent-validation") {
      options.validateAgents = false;
    } else {
      fail(`unknown option ${flag}`);
    }
  }
  return options;
}

function readPolicy(policyPath) {
  let parsed;
  try {
    parsed = JSON.parse(readFileSync(policyPath, "utf8"));
  } catch {
    fail(`${policyPath}: cannot read valid JSON`);
  }
  return validatePolicy(parsed, policyPath);
}

function collectFiles(directory) {
  const output = [];
  const walk = (current) => {
    for (const entry of readdirSync(current, { withFileTypes: true })) {
      const child = join(current, entry.name);
      if (entry.isDirectory()) walk(child);
      else if (entry.isFile() && entry.name.endsWith(".md")) output.push(child);
    }
  };
  walk(directory);
  return output;
}

function verifyRoleReferences(policy) {
  const known = new Set(policy.responsibilities);
  const matcher = /<!--\s*df-role:\s*([a-z][a-z0-9_]*)\s*-->/g;
  const unknown = [];
  for (const tree of SKILL_TREES) {
    for (const file of collectFiles(tree)) {
      const content = readFileSync(file, "utf8");
      for (const match of content.matchAll(matcher)) {
        const candidate = match[1];
        if ((candidate.includes("_") || candidate === "escalation") && !known.has(candidate)) {
          unknown.push(`${file}: ${candidate}`);
        }
      }
    }
  }
  if (unknown.length > 0) fail(`skill role reference is not declared: ${unknown.sort()[0]}`);
}

function verifyNamedAgents(policy) {
  for (const harness of ["claude", "codex"]) {
    for (const responsibility of policy.responsibilities) {
      for (const lane of policy.lanes) {
        validateNamedAgents(harness, policy.roles[harness][responsibility][lane]);
      }
    }
  }
}

function main() {
  const options = parseArgs(process.argv.slice(2));
  const policy = readPolicy(options.policy);
  verifyRoleReferences(policy);
  if (options.validateAgents) verifyNamedAgents(policy);
  process.stdout.write(`Model policy OK: ${policy.responsibilities.length} responsibilities, ${policy.lanes.length} lanes\n`);
}

try {
  main();
} catch (error) {
  process.stderr.write(`${error instanceof Error ? error.message : String(error)}\n`);
  process.exitCode = 1;
}
