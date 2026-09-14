# Licensing scope and history

Accountant's licensing model keeps the source public for private personal use,
study, testing, and contributions while reserving product reuse and distribution
for Oleksandr Mazur and people separately authorized in writing. The
[source available license](../LICENSE) applies to newly licensed material in
the iOS app, AccountantCore, tests, documentation, and assets, with the exceptions
it states. Private personal use does not include providing the source or builds
to other users or operating the Software for a business.

This is a custom legal draft, not a legal opinion or a guarantee of exclusive
rights. Have a qualified lawyer review the license and contributor assignment
for the relevant jurisdiction before relying on them commercially. In
particular, a repository notice cannot establish ownership that has not been
verified or complete a contributor's copyright transfer.

## The MIT baseline remains reusable

The repository began with the MIT License in commit
[`49dd55ed1ae4470c8259fd61955d81e17f74cbcc`](https://github.com/sqcode06/accountant-app/commit/49dd55ed1ae4470c8259fd61955d81e17f74cbcc),
dated January 3, 2026. Its copyright notice names Oleksandr Mazur.

At the September 13, 2026 licensing review, GitHub reported the repository as
public. Its `main` branch was at
[`119d433b8ad2f8e56b7c2e46cfdd2b03f523cffb`](https://github.com/sqcode06/accountant-app/commit/119d433b8ad2f8e56b7c2e46cfdd2b03f523cffb),
and its published `redesign/ia-design-core` branch was at
[`7037459e6337a146332cde280f31d1d3ccfbccd2`](https://github.com/sqcode06/accountant-app/commit/7037459e6337a146332cde280f31d1d3ccfbccd2).
Both carried MIT terms. The latter is the baseline for this working-tree change.

At that review, the source available terms existed only in the uncommitted
working tree. Drafting them did not change the licence of anything already
published. The transition begins with the first published commit containing the
new `LICENSE`; Git history identifies that commit without imposing a retroactive
September 13 cutoff.

Those published versions, and material already supplied under MIT elsewhere,
remain usable under MIT. Someone may continue developing and distributing an
independent fork from that material, including commercially, while complying
with MIT's notice requirements. Changing LICENSE, making later edits, removing
a public branch, or making the repository private does not take those existing
permissions back. See [GitHub's guidance on changing licenses](https://opensource.guide/legal/#what-if-i-want-to-change-the-license-of-my-project).

The complete historical [MIT notice](../licenses/MIT-legacy.txt) is retained.
It covers the previously licensed material, including when that material is
carried into later versions. It does not automatically cover new copyrightable
additions first published under the source available license. Git history and
the license distributed with each version establish the relevant boundary;
this document does not impose a separate retroactive calendar cutoff.

## Public access and ownership

- **GitHub forks:** public repositories permit viewing and forking through
  GitHub under [its Terms of Service, section D](https://docs.github.com/en/site-policy/github-terms/github-terms-of-service#d-user-generated-content).
  The license preserves those platform permissions and permits contribution
  forks. A fork does not by itself transfer ownership of the original work.
- **Open source terminology:** restrictions on reuse and distribution mean the
  new terms are source available, not open source under the
  [Open Source Definition](https://opensource.org/osd).
- **Distribution:** being an iOS app is not a technical guarantee against other
  people distributing builds. Apple supports [several distribution methods](https://developer.apple.com/documentation/xcode/distributing-your-app-for-beta-testing-and-releases).
  The license therefore addresses app builds, source, components, and modified
  versions, subject to the MIT exception.
- **Ideas and branding:** the license does not claim ownership of accounting
  concepts or independently written implementations. Copyright protects
  expression, not ideas or methods; see the [U.S. Copyright Office's explanation](https://www.copyright.gov/register/tx-programs.html).
  Trademark rights are a separate question; the notice does not establish a
  registered trademark or promise exclusivity in the name "Accountant."

## Contributions and provenance

[CONTRIBUTING.md](../CONTRIBUTING.md) requires a separate signed
[copyright assignment](ContributorAssignment.md) for original contributions
from others before merge. A broad contributor license could provide commercial
control while leaving contributors as copyright holders; assignment is used
here because the stated goal is ownership of the contributed copyright.
Assignment formalities vary; for example, [U.S. law requires a signed writing](https://www.copyright.gov/title17/92chap2.html#204).

Before assignment, the contributor retains ownership. Submission grants the
maintainer only the limited permission stated in the source available license to
retain, inspect, build, run, and test the proposed contribution, including in CI,
for review. It does not authorize incorporation, distribution, release, or
product reuse. Those activities require the signed assignment or other separate
permission from the contribution's rights holder.

The inspected history contains a commit credited to Nataliia Burmistrova:
[`84bea5bc31f37980f31d954a0014a5905955814f`](https://github.com/sqcode06/accountant-app/commit/84bea5bc31f37980f31d954a0014a5905955814f).
It changes Xcode signing, bundle identifiers, and deployment settings.
Oleksandr Mazur confirmed that he authored this change and that the recorded
author name resulted from an incorrect Git user configuration. The contribution
process therefore treats it as the owner's own work, for which no contributor
assignment is required. Its existing MIT permissions and history are preserved.

The inspected Swift package declares no external package dependencies; the
Xcode project references the local AccountantCore package. That check is not an
audit of every asset or copied snippet. Separately licensed material retains
its notices and license, and must not be represented as assigned original work.
