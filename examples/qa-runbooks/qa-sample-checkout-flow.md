# QA Acceptance Runbook: Sample Checkout Flow

## Scope
Validate that a user can add an item to cart, complete checkout, and view order confirmation.

## Preconditions
- Test account exists: `qa.user@example.test`
- Product catalog contains at least one in-stock item
- Payment sandbox is enabled

## Test Cases

### TC-001 Add Item to Cart
1. Open the app home page.
2. Search for `Sample Item`.
3. Open product details.
4. Click `Add to Cart`.
Expected:
- Cart badge increments to `1`
- Added item appears in cart drawer

### TC-002 Complete Checkout
1. Open cart page.
2. Click `Checkout`.
3. Fill shipping fields with valid data.
4. Select `Standard Shipping`.
5. Enter sandbox payment details.
6. Click `Place Order`.
Expected:
- User is redirected to confirmation page
- Confirmation page shows order number

### TC-003 Verify Order History
1. Open user profile menu.
2. Navigate to `Order History`.
3. Find most recent order.
Expected:
- Order status is `Processing` or `Confirmed`
- Line items and totals match checkout summary

## Negative Case

### TC-004 Invalid Payment Card
1. Repeat TC-002 with an invalid sandbox card.
Expected:
- Checkout is blocked
- Inline error message explains payment failure
- Cart contents remain unchanged

## Out of Scope
- API penetration testing
- Security scanning
- Performance benchmarking

## Pass Criteria
- All critical test cases (TC-001, TC-002, TC-003) pass
- No blocking UI defects
