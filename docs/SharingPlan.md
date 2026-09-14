# Optional accounts and sharing: implementation plan

Status: proposed development sequence, 2026-09-14. No backend, login, or shared
ledger has been implemented. The personal TestFlight beta proceeds independently.
The [roadmap](Roadmap.md) is the short product overview.

**Network-source policy, confirmed by the owner on 2026-09-15.** Publish new
network and service implementation for transparency, review, and contributions.
Permit inspection and isolated local builds, modifications, and tests needed
for auditing or preparing improvements for Accountant. Independent hosting,
including a private personal server, deployment for other users, and reuse of
the protected implementation in another product require the owner's separate
permission. Normal use of the official app and service remains governed by
their applicable terms; source inspection does not grant production access.

Accept bug reports and proposed fixes. Before incorporating another person's
original code, follow the existing signed
[contributor assignment process](../CONTRIBUTING.md). Genuine authorship and
ownership are separate; accepting a pull request alone transfers neither.

Before the first publication of network code, identify the exact files covered
and apply reviewed, specifically scoped terms. The current root license permits
private personal use and does not by itself express this stricter policy.
Keep the existing personal-app permissions, earlier MIT material, and third-party
licenses intact. In particular, already-published MIT merge primitives do not
become restricted merely by being used in the new service. This paragraph
records the intended policy; it does not change the current license or license
code that has not yet been written. See [Licensing.md](Licensing.md).

1. **Choose and prove the service boundary.** Evaluate managed authentication
   and transactional storage in a disposable development environment using
   synthetic finances. The service must verify identity, check current ledger
   membership on every read/write, and atomically validate and apply changes.
   Validate exact monetary amounts, currencies, references, and double-entry
   balance on the server even when client checks are bypassed.
   Prefer managed identity over implementing passwords or token verification
   ourselves. Record the vendor, costs, data location, retention, recovery, and
   encryption model before provisioning production. Encryption in transit and
   at rest must not be described as end-to-end encryption.

   Acceptance: unprivileged clients cannot read or change another ledger, send
   an unbalanced transaction, or reference another ledger's accounts. Tests
   exercise the real service boundary, not only a mocked Swift interface.

2. **Separate profiles from financial records.** Give Accountant users stable
   internal IDs independent of provider email. Link an additional Apple/Google
   identity only through an explicit authenticated flow. Introduce stable ledger
   IDs and isolate local stores and pending changes by profile and ledger.
   Existing local finances migrate without becoming uploaded or shared.

   Acceptance: sign-in alone uploads no financial records; switching profiles
   cannot expose the previous profile's cache or submit its pending work. Tests cover equal
   provider emails, Apple relay addresses, linking failures, and sign-out while
   requests are in flight. Local-only use remains available without a session.

3. **Prove syncing between two devices before invitations.** Start with a
   development slice: one identity, one explicitly enrolled ledger, two clients,
   and account creation plus a balanced transaction. Persist the local change
   and its outgoing operation together before showing it as saved locally.
   The server assigns revisions and applies each stable operation ID once;
   reusing an ID with different contents fails. A lost response can be retried
   without adding the transaction twice. A stale edit is rejected for explicit
   resolution. Snapshots and change cursors must describe the same revision.

   Acceptance: interrupt each send/save/acknowledgement boundary; reorder and
   repeat requests; edit from two offline clients. They converge without lost
   or duplicated money. Add drafts, confirmation, budgets, ordered import rules,
   reconciliation state, and deletions before exposing sync for a whole ledger.
   A narrow prototype must never imply that unsupported records are protected.

4. **Finish identity and data lifecycle behavior.** Add the native Apple and
   Google login flows once provider setup is available. Show local/syncing/synced
   states and understandable conflict actions. Define local-cache removal,
   stopping sync, account deletion, and shared-ledger deletion separately.
   Restore into a new private ledger by default; replacing an existing synced
   ledger needs explicit permission and a new generation that rejects old queued
   writes. Deletions cannot reappear from a stale device. Warn about unsent
   changes before a user discards their local copy.

   Acceptance: exercise expiry, revocation, sign-out, deletion, restore, and old
   devices returning online. Complete in-app account deletion, token revocation,
   and revised privacy disclosures before releasing registration.

5. **Add shared ledgers.** Begin with owner/editor/viewer roles and explicit,
   expiring invitations. Joining opens the shared ledger without moving private
   records into it. Enforce roles and current membership in the same server
   transaction as each command; an old login token cannot preserve removed
   access. Set rules for leaving, owner transfer, and deleting a shared ledger.

   Acceptance: two users using different login providers can collaborate; a third
   cannot guess access. Test invite replay, simultaneous edits, revocation while
   offline, and member removal during sync. Removed members receive no further
   server data. Previously downloaded records or screenshots cannot be remotely
   made unseen; explain that limit when inviting someone.

The local atomic snapshot remains useful for durable storage, but uploading
whole files or calling `mergeFinalized(from:)` does not satisfy these contracts.
Server checks must protect monetary and reference invariants even when a client
is outdated or bypasses Swift validation. Keep domain examples shared between
client and server tests. Finalized history must preserve its existing rules.

**Service-selection issue to resolve:** Supabase is a candidate, not a decision.
Its documented default automatically links identities with matching emails,
which conflicts with the explicit-linking policy above. Verify whether a
supported configuration can satisfy that policy; otherwise choose another auth
provider. Do not assume enabling manual linking disables automatic linking.
[Supabase identity-linking documentation](https://supabase.com/docs/guides/auth/auth-identity-linking).

Apple's login and account-deletion requirements should be rechecked when this
feature ships. The planned Apple/Google pair and in-app deletion must be tested
with real provider configuration.
[App Review guidelines](https://developer.apple.com/app-store/review/guidelines/),
[account deletion](https://developer.apple.com/support/offering-account-deletion-in-your-app/).
