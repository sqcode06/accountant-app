# What needs your review

This is the short owner checklist. Engineering fixes, automated tests, and code
review continue without waiting for you to go through the repository on a phone.
Nothing on this page asks you to enroll with Apple or publish now.

For your next build, use `main`. The earlier stabilization branch is retained
for history; the consolidation keeps the same tested app behavior.

**When the next tested iPhone build is convenient**

1. **Check that the money behavior matches your expectations.** A draft purchase
   already counts toward its category's budget. Confirming it must not count it
   twice. Stopping a limit affects the selected month onward; earlier limits and
   recorded spending remain. Spending can appear under “Not budgeted” after Stop.
   We test the calculations; your part is confirming this is how you want the
   app to behave and that the screen explains it clearly.
2. **Use a real statement through Files.** Check the chosen bank account, dates,
   amounts, currency, fees, and a few category suggestions before accepting it.
   The automated import tests bypass the system file picker. LHV still needs a
   representative export to verify its column format. Use a copy with identifying
   details removed if sharing an example; retain the columns and number/date
   formatting needed to diagnose parsing.
3. **Export and restore a disposable test dataset.** Save a backup through the
   actual share sheet and select it again through Files. Read the confirmation
   before restoring or erasing: restore replaces current finances; erase clears
   active finances but keeps existing backups and protected recovery copies.
   Test this on disposable data, not your only copy of real finances.
4. **Check notifications on your phone.** With a draft pending, choose a nearby
   reminder time and check actual delivery while the app is closed. Then confirm
   the draft, change permission in iOS Settings, and check the in-app explanation.
   These are one-shot reminders, scheduled from the current queue when the app
   refreshes it; they are not guaranteed daily follow-ups while the app stays
   unopened. iOS settings such as Focus can affect delivery.
5. **Flag confusing or inaccessible screens.** In particular, try your preferred
   text size and theme. For a problem, record the screen, what you did, what you
   expected, what happened, and the build being tested. A screenshot helps; keep
   private financial details out of public issue reports.
6. **Try accounts and matching a bank statement.** Archiving hides an account;
   its history stays, and you can restore it. On Reconcile, use the bank's closing
   balance and statement date, then tick entries you find on that statement.
   This marks them cleared for this account; it does not move money. Reconciliation
   excludes drafts and stops at the selected date. Account activity includes
   drafts and future-dated entries. Confirm drafts in Review before reconciling
   them. An empty checklist can still have a difference, and matching totals do
   not prove every entry has been checked.
7. **Check reconciliation wording and readability.** Distinguish the bank's
   “Statement balance” from the sum labelled “On statement”; “Cleared” may be a
   clearer name for the latter. Check whether the difference's direction and the
   input's currency are clear. Long transaction descriptions are shortened to one
   line: check that you can still identify the correct entry before ticking it.

**Before you distribute a beta**

- Read the app description and known limitations. It is a personal, local app;
  Apple/Google login, shared ledgers, currency conversion, debt forecasts, and AI
  must not be advertised as available yet. Check the iPad layout as well if the
  build continues to support iPad.
- Review the [license summary](Licensing.md), including the treatment of earlier
  MIT material, and the final public privacy statement. Your private-personal-use
  policy is already recorded; no new licensing decision is being requested here.
  Check that the published developer/support details are the ones you want.
- Choose the testers and review the remaining known issues for the exact build.
  Signing and upload are a later step in [TestFlight preparation](TestFlight.md).

**When sharing development reaches a concrete proposal**

Before network source is first published, review which files its terms cover:
public inspection, isolated auditing, and contributions are intended to be
allowed; independent hosting and product reuse require your permission. The
current license permits private personal use, so the stricter network terms
need separate wording and legal review. Keep the personal app's existing
permissions and the earlier MIT grants intact. This records your decision;
it is not another request to choose a policy now.

Review who can see or change a shared ledger, how invitations and leaving work,
and exactly what happens to private data on enrollment, sign-out, restore, and
deletion. Also review the proposed service's cost, data location, retention, and
privacy wording before real finances are sent there. The
[sharing plan](SharingPlan.md) keeps those choices separate from the personal app.

The latest automated results and remaining manual limits are recorded in
[AppTesting.md](AppTesting.md). Passing tests are evidence for the behavior they
exercise; they do not replace your decision about what to publish.
