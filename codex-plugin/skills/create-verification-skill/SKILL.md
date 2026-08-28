---
name: create-verification-skill
description: "Generate a project-local verification skill that drives the target app the way a user does, any language, framework, or platform. One skill per user-facing medium when a repo has several. Use for $create-verification-skill, \"make a verification skill for this repo\", or when a project has no scripted way to prove UI, CLI, or service behavior."
---

# Create a verification skill

Every serious project needs a scripted way to drive the real app and prove behavior: launch it, exercise a feature the way a user would, and capture evidence. This skill generates that as a project-local skill tailored to the repo, written into the target repo's own skill directory. Use `.agents/skills/verify-<app>/` when the repo already has that convention, else `.claude/skills/verify-<app>/`. You write the generator's output for the next agent, not for a human. It will be read cold, mid-task, by an agent that has never seen the app.

## 0. Inventory what the repo already has

Never generate over the top of existing work. A repo that has been worked on
for a while usually has pieces of this already: a dev-stack skill, an e2e
harness, a sandbox or workbench helper, a provisioning script. List the repo's
own skill directories and its scripts before writing anything.

For each thing you find, decide one of three, and say which in the handover:

- **Adopt.** It already drives a real surface. The generated skill points at it
  rather than restating it.
- **Absorb.** It is a fragment, a launch command or a single recipe. Fold it in
  and delete nothing without asking.
- **Leave.** It is unrelated to driving the app.

Consolidating beats generating. A second skill that launches the app a slightly
different way is how a repo ends up with two answers to one question.

## 1. Interview the repo, not the user

Answer these from the codebase and only ask the user what you cannot observe:

- **Surface.** What does a user actually touch? A web UI, a CLI or TUI, a desktop app, an API, a mobile app, a library? A repo can have several, and a real product usually does.
  - One medium, one skill. Two media that are driven completely differently, a web dashboard and an interactive TUI say, get one skill each: `verify-<app>-<medium>`. Their launch, drive, and evidence recipes share almost nothing, and a single skill that tries to cover both is read cold by an agent that then picks the wrong half.
  - When you generate more than one, also write a short `verify-<app>` index skill whose only job is to name the media and say which skill drives which. That is the one an agent reaches for when it does not yet know the surface.
  - Do not split a medium by feature. The feature map handles that.
- **Run.** How does the app start locally? Prefer the repo's own documented dev command (package scripts, Makefile, README quickstart). Note ports, env vars, seed data, auth.
- **Drive.** How can an agent interact with it programmatically? Existing harnesses first: Playwright or Cypress specs, expect scripts, PTY helpers, curl-able endpoints, a debug port. Only then pick a generic recipe: agent-browser for web UIs and Electron, the tmux workbench pattern for TUIs and interactive CLIs, plain CLI execution (plus curl for services) for everything else.
- **Observe.** What evidence can be captured? Screenshots, terminal transcripts, response bodies, logs, exit codes, DB state.
- **Isolate.** Can two instances run side by side (ports, data dirs, profiles)? If not, say so in the generated skill. Refusing to double-drive a shared instance beats corrupting the user's session.

If the checkout doesn't build or start as-is, fix that first (or report it precisely) before generating. A skill written against a broken base teaches wrong steps. When an irrelevant missing asset blocks startup (a static dir the API never serves, a sample config), the generated skill may create it, clearly marked as verification scaffolding, and remove it in cleanup.

## 2. Generate the skill

Write `SKILL.md` in the chosen skill directory. The YAML frontmatter carries `name: verify-<app>` and a `description` that names the app, the surface, and when to reach for it. Without frontmatter the skill never registers. The body has these sections, each grounded in what the interview actually found, no placeholders left:

- **Launch.** The exact command that starts the app for verification, and how to tell it's ready (a log line, a port answering, a prompt). Include teardown. For a short-lived CLI or TUI there is no server to keep alive. Launch then means build the binary (or install deps) once, then start each drive in its own isolated PTY or tmux session.
- **Doctor.** One read-only check that answers "is this instance worth driving?" Process up, right version or build, port owned by us, auth valid. An agent runs this first whenever anything looks off.
- **Drive.** The harness recipe with real selectors and commands from this repo, not examples. Prefer stable handles (ARIA labels, data attributes, prompt strings, route paths) over coordinates and tab order.
- **Evidence.** What to capture for a proof and where it goes. State the proof standards: exercise the real user path, not internal setters or test-only endpoints. Capture the action and the resulting state, not just the final screen. Verify side effects (files written, rows inserted, messages sent) alongside what's visible. Mocks only where a production boundary already isolates the external system. When the safe path is a dry-run or test mode, verify what it actually skips by observing (files, network, git refs) rather than trusting its name. Some dry-runs still touch the network or open a browser.
- **Cleanup.** How to tear down instances the run created. Never kill by process name. Kill what you started. Cleanup removes instances and scratch state, never the evidence. Proof artifacts survive the teardown, in a location the skill names.
- **Helpers.** Any script the skill ships is executable and its invocation is shown in the skill body. A helper the reader has to reverse-engineer is not a helper.

## 3. Seed the feature map

Create `features/README.md` in the skill directory plus one file per user-facing feature you can identify (aim for the top 3 to 5 to start, from routes, commands, menus, or docs). Follow the shape in [`references/feature-map-example/`](references/feature-map-example/), with a README index and one file per feature. Each file answers, from the user's point of view, what the feature is, how to reach it, how to drive it with the harness, and what observable end state proves it works. The four H2s are `Sub-features`, `How to get to it (user POV)`, `Driving it with <harness>`, and `Gotchas`. When the project keeps a product catalog, each feature file carries a `Catalog IDs:` line directly under its opening paragraph naming the catalog entries it covers, so review scoping and acceptance can key on them. Name the catalog and where it lives in the skill body; that pointer belongs to the project, not to df. The map is the repo's maintained verification source. A proof that drives one convenient entry point is incomplete when the map lists others.

## 4. How df finds it

Nothing to register. The skill is a skill: the harness loads it from the repo's
own skill directory and its frontmatter `description` is what makes an agent
reach for it. That is the whole discovery mechanism, so the description has to
earn it. Name the app, name the medium, and name the moment ("use before
claiming a dashboard change works").

df writes no config into the target repo, and no df file is committed there.
A verification skill is the project's own asset. It stays useful if df is
never used again.

Two consequences worth stating in the handover:

- The skill and its `features/` map are committed. They travel with a branch,
  and a change to either is a code change that gets reviewed like one.
- The generated skill must not name df, its skills, or its stage vocabulary.
  A teammate reading it should see a way to drive their app, not a pipeline
  artifact.

## 5. Prove the generated skill before handing it over

Run its own instructions end to end once: launch, doctor, drive ONE mapped feature (one is enough, the map exists so later runs can cover the rest), capture evidence, clean up. After cleanup, confirm the evidence still exists at the named location. A cleanup that eats the proof fails this step. Fix what fails, and run the generated cleanup after every failed iteration too, so broken attempts don't strand processes and ports. A generated skill that was never executed is a draft, not a deliverable.

## 6. Offer the maintenance loop

Point the user at `$maintain-verification-skill` for keeping the map honest as the app changes. Suggest a cadence only if they ask.
