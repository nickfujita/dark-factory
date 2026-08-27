# Blinding rules for live scenarios

A live scenario spawns a real session and grades its transcript. The failure mode is the observer effect. An agent that knows it is being evaluated behaves differently, so the session under test runs blind.

## Non-negotiables

- No `eval`, `test`, `judge`, `experiment`, `rubric`, `score`, `compare`, `benchmark`, `candidate`, or `arena` in any directory name, file name, or prompt the session can see. That includes the scratch directory it runs in. A session can read its own cwd.
- The prompt states the goal, not the meta. "There is a bug in bug.sh, fix it", not "show me how you follow the router contract".
- No chain-eliciting cues. Do not ask the session which skills, principles, or files it applied. That meta-prompt inflates citation behavior. Ask for the work, then grade chain-following from the transcript.
- Sanitize directory and slug names. Use project-shaped names an operator might pick, never labels like `case-1` or `agent-a` in anything the session sees.
- Write the pass criteria for the grader only. Hold them back from the session under test. Three to six concrete criteria per scenario.
- Plant the context an organic task would have. A project skeleton, the skill under test installed the way it would really be installed, a real file to chew on.

## Grading

- Grade from the emitted transcript, the files the session touched, and the store files. Never from the reply's claims. The stream-json transcript the harness captures is the record. `scripts/test-df-invocation.sh` shows the pattern. Detect engagement from tool calls and file reads, not from what the reply says happened.
- Chain-following is graded from the files the session really read, plus the shape of what it produced. Citing a principle is not reading its file, and reading it is not applying it.
- The grader can know it is grading. It sees outputs by sanitized label only, never a model name. Graders resolve through the `eval_graders` role in `../../df/references/model-policy.md`.
- Read the session output yourself end to end and compare against the grader's verdict. Disagreement means the grader is biased or the criteria are ambiguous. Resolve it before recording the result.

## Comparative runs

Not the default. A scenario runs one candidate against pass criteria. When the operator explicitly asks for a comparative run:

- Do not tell either candidate the other exists.
- One judge scores both sets in a single pass on one scale, blind to which set each came from. Two judge runs with different prompts do not compare. The calibration drifts.
- Each candidate works in its own sanitized directory on the same prompt.
