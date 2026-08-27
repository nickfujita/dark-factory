# Spec Guardian Rules

The QA runbook must describe what the USER sees and does. It must never
reference internal implementation details. These rules are enforced during
generation and checked during multi-model validation.

## Scope

These rules apply ONLY to browser automation test cases (TC-xxx).
Programmatic test specifications (UT-xxx, IT-xxx, ET-xxx) are exempt because
they are technical specifications that necessarily reference code modules,
API endpoints, and data structures.

## Forbidden Content

The following must NOT appear in any test case:

1. **Code identifiers**: class names, function names, variable names,
   module paths (e.g., `UserService`, `handleSubmit`, `src/components/`)

2. **API endpoints**: URL paths that are not user-visible
   (e.g., `/api/v1/users`, `POST /auth/login`)

3. **Database references**: table names, column names, SQL
   (e.g., `users table`, `org_id column`, `SELECT * FROM`)

4. **Internal architecture**: references to queues, caches, workers,
   middleware, hooks, state management internals
   (e.g., `Redis cache`, `background worker`, `useEffect hook`)

5. **HTTP details**: status codes, headers, request/response bodies
   (e.g., "returns 200", "Authorization header", "JSON response")

6. **Test framework internals**: test IDs used as primary identifiers
   (data-testid is allowed only as a parenthetical hint, not as the
   primary way to identify an element)

7. **Infrastructure and configuration**: environment variable names
   (`NEXT_PUBLIC_API_URL`), config file paths (`config/database.yml`),
   service names (Redis, S3, Kafka), deployment targets, CI/CD references
   (e.g., `set DATABASE_URL`, `deploy to staging`, `runs in Docker`)

## Allowed Content

- UI element labels ("Add to Cart" button, "Email" field)
- Visible text on the page
- User-facing URLs (the URL bar content, not API routes). URLs like
  `/products/new` or `/users/123/edit` are allowed if they appear in the
  browser's address bar.
- Page titles and headings
- Error messages as displayed to the user
- data-testid hints in parentheses as supplementary info

## Self-Correction Process

If any test case violates these rules:
1. Identify the violation
2. Rewrite the step or assertion using only user-visible language
3. If the requirement can only be tested through internal inspection
   (e.g., "data must be encrypted at rest"), flag it as UNTESTABLE
   in the coverage matrix

## Examples

**Category 1 — Code identifiers:**
Bad: `Check that UserService.create() was called`
Good: `VERIFY text "Welcome, Jane" visible in element matching "header greeting"`

**Category 2 — API endpoints:**
Bad: `Call POST /api/users with payload {...}`
Good: `Click "Create Account"`

**Category 3 — Database references:**
Bad: `Verify the users table has a new row`
Good: `VERIFY text "Account created" visible in element matching "success banner"`

**Category 4 — Internal architecture:**
Bad: `Wait for the background job to complete`
Good: `Wait for element matching "processing complete" notification to appear`

**Category 5 — HTTP details:**
Bad: `VERIFY response status is 200`
Good: `VERIFY text "Profile updated" visible in element matching "success notification"`

**Category 6 — Test framework internals:**
Bad: `Click element with data-testid="submit-btn"`
Good: `Click "Submit" (data-testid: "submit-btn")`

**Category 7 — Infrastructure and configuration:**
Bad: `Set STRIPE_API_KEY to test key before proceeding`
Good: `Navigate to the payment page` (precondition: test payment provider configured)
