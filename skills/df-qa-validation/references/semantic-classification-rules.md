# Semantic Classification Rules

Every finding from the validation round must be classified as either
**non-semantic** (auto-fixable) or **semantic** (proposed as a diff for
user approval). When in doubt, classify as semantic — it is safer to
ask than to auto-apply a meaning change.

## Non-Semantic (auto-fixable) — tag as `[AUTO-FIX]`

These changes do not alter the meaning of any requirement or test case:

1. **Formatting inconsistencies**: Markdown structure, heading levels, list
   styles, whitespace, line breaks that don't affect meaning
2. **Wording clarity**: Rephrasing for readability without changing what is
   tested or required (e.g., "Click the button" -> "Click the 'Submit' button")
3. **Traceability link corrections**: Fixing mismatched references
   (e.g., TC says `REQ-003` but means `REQ-3`, or a TC traces to a
   requirement that was renumbered)
4. **Deduplication**: Removing test cases that test the exact same scenario
   as another TC (same steps, same assertions, same requirement)
5. **YAML frontmatter fixes**: Correcting dates, IDs, paths, or formatting
   in the runbook's YAML frontmatter
6. **Coverage matrix corrections**: Updating the coverage matrix table to
   match the actual TCs present in the document (adding missing rows,
   removing rows for deleted TCs)
7. **Spec guardian violations**: Rewriting steps/assertions that contain
   implementation details to use user-visible language (same rules as
   `df-verify-coverage/references/spec-guardian-rules.md`)

## Semantic (proposed for user review) — tag as `[PROPOSED]`

These changes alter the meaning of a requirement or test case:

1. **Adding a requirement**: A new REQ-xxx or NEG-xxx that doesn't exist
   in the PRD
2. **Removing a requirement**: Suggesting a requirement should be dropped
3. **Changing requirement meaning**: Altering what a requirement asks for
   or what "done" looks like
4. **Adding a test case**: A new TC-xxx that tests something not currently
   covered
5. **Removing a test case**: Suggesting a TC should be dropped (other than
   deduplication of exact copies)
6. **Changing test expectations**: Altering what a TC's assertions verify
   (different expected outcome)
7. **Scope changes**: New user flows, removed functionality, changed
   boundaries
8. **Changing preconditions**: Modifications that affect test validity or
   what is assumed true before testing
9. **Changing priority**: Moving a requirement or TC between priority levels
   (e.g., P0 -> P1)

## Edge Cases

- Fixing a typo in a requirement name: **non-semantic** (if the intent
  is obviously the same word misspelled)
- Rewriting a vague assertion to be specific: **semantic** (it changes what
  the test actually verifies)
- Adding a missing traceability link to an existing TC: **non-semantic**
- Adding a traceability link to a requirement that doesn't exist:
  **semantic** (implies a new requirement)
