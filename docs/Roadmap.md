# Where Accountant goes next

Updated 2026-09-14. The first beta is the personal app. We can develop sharing
alongside it; Apple enrollment and TestFlight publication can wait.

For the small set of things that need the owner's attention, use
[What needs your review](OwnerReview.md). Engineering work continues alongside it.

**Now: make the existing app dependable.** Budget navigation, import rules, and
restore/erase have automated iOS coverage. An interrupted restore or erase now
keeps the saved finances together. Budget actions now await saving, and failed
Stop saves can be retried. Reminder permission changes and competing scheduling
requests have regression tests. These latest changes are awaiting native CI.
The old Budget Stop exit no longer reproduces
on the user's iPhone; we have not established its cause.

Before the personal beta, finish these checks:

- Confirm actual reminder delivery and the permission explanation on an iPhone.
- Exercise import, backup export, and restore through the real iPhone file
  picker and share sheet; the automated fixtures bypass file selection.
- Verify LHV's import columns against a real export, then finish the remaining
  account, budget, review, and reconciliation checks.

The [engineering checklist](AppReliabilityPlan.md) keeps the detailed evidence.
The [TestFlight page](TestFlight.md) keeps distribution steps separate.

**Next: optional accounts and reliable syncing.** Someone can keep using
Accountant alone, offline, without registering. Signing in will create an
Accountant profile; it will not upload existing finances. The user separately
chooses which records to sync. Apple and Google are the intended login options.

First prove one person's records survive two devices, lost connections, retries,
and conflicting edits. Then add invitations so two people can use a shared set
of records. Personal and shared records stay separate. The app must explain what
is saved locally, waiting to sync, or needs a decision. This is planned work;
there is no working sign-in or sharing service yet. The
[implementation plan](SharingPlan.md) breaks it into deliverable steps.

**Then: debts and upcoming payments.** Show what you and your household owe,
who owes it, due dates, minimum payments, and interest or fees. Paying a debt
links to a real transaction. Terms need to be entered or verified for each
product; knowing a bank's name does not determine its interest rules. Start with
recording balances and payments, then add calculations for supported terms.

**After that: see the month ahead.** Add recurring bills and expected income,
then a calendar and cash forecast. Try questions such as “What if my income
arrives a week late?” Predictions show their assumptions and remain separate
from actual transactions. Currency conversion needs explicit rates before
balances in different currencies can become one meaningful total.

**Later: reduce the manual work.** Improve statement support and duplicate
review, recognize merchants, learn from corrections, and explore receipts and
bank connections. Suggestions stay reviewable. Charts can make the existing
data clearer without changing the accounting rules.

**Finally: an optional adviser.** AI can explain a forecast, compare payment
scenarios, and point to the records and assumptions behind its suggestions.
The accounting engine calculates the money. Advice does not silently change
transactions or make payments; using an external AI service needs its own
explicit data-sharing choice.

This is an order of dependencies, not a promise to build every item before
anyone can use the app. The personal beta is useful on its own.
