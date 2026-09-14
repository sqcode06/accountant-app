# Personal beta: TestFlight preparation

Decision, 2026-09-14: release the personal app first. Apple Developer enrollment,
App Store Connect setup, and publication are deferred until the owner is ready.
Sign-in and sharing are separate development work.

**What we can check now**

- Core tests and native app/UI tests remain the reliability gates.
- The iOS workflow builds Release on both supported test runtimes. Its Xcode
  26.2 job also creates an unsigned Release archive for a generic iOS device
  and checks the packaged privacy manifest and app metadata. Logs and metadata
  are retained with native diagnostics. This checks device compilation and
  packaging; it does not validate signing or App Store acceptance.
- The shared `AccountantApp` scheme archives Release. The current bundle ID is
  `dev.sqcode.AccountantApp`; version is `1.0`, build `1`, minimum iOS is `18.0`.
  iPhone and iPad are enabled, so both need checks before external distribution.
- The app privacy manifest declares app-only `UserDefaults` access (`CA92.1`),
  no tracking, and no collected data for the current local-only app. Audit it
  again whenever networking or an SDK is added. The manifest is separate from
  App Store Connect privacy answers and a public privacy policy.

Current test evidence and its limits are in [AppTesting.md](AppTesting.md).
The remaining product checks are in the [roadmap](Roadmap.md).

**When ready to distribute**

1. Enroll in the Apple Developer Program. Confirm the bundle ID and create the
   matching App Store Connect app record. Choose the enrolled team in Xcode;
   the project's existing team value does not establish membership or ownership.
2. Finish the beta's reliability checks. On an iPhone, test fresh installation,
   upgrading existing data, onboarding, denied/allowed reminders, import and
   restore through Files, export through the share sheet, and background/relaunch.
   Preserve a backup before migration testing. Check the iPad layout too.
3. Use the shared scheme in Xcode on a Mac with a currently accepted SDK. As of
   this date, Apple requires Xcode 26 or later and the iOS 26 SDK or later for
   uploads. Recheck before release.
4. Keep a release record: commit, Xcode version, marketing version, build number,
   and device results. Before **each new upload**, set a larger, unused integer
   in the app target's **General → Identity → Build** field (the
   `CURRENT_PROJECT_VERSION` setting). Do not reuse the checked-in `1` for
   successive builds or confuse a CI run number with an uploaded beta version.
5. Archive for an iOS device, validate the signed archive in Xcode Organizer,
   and upload it to App Store Connect. Complete beta information and export
   compliance questions based on the actual build; no answer is prefilled by
   this repository. Prepare accurate privacy answers and a public policy.
6. Check the processed build, test through TestFlight, and then invite external
   testers when ready. The first external build needs Apple's beta review.
   Review the code and device results for that exact build before distributing.

There is no signed-export or upload workflow, and no signing credentials have
been added. Neither the unsigned archive nor passing simulator tests is a
published beta.

Apple references, checked 2026-09-14:
[uploading builds](https://developer.apple.com/help/app-store-connect/manage-builds/upload-builds),
[SDK requirements](https://developer.apple.com/news/upcoming-requirements/),
[TestFlight](https://developer.apple.com/testflight/),
[app privacy](https://developer.apple.com/help/app-store-connect/manage-app-information/manage-app-privacy),
[required-reason APIs](https://developer.apple.com/documentation/bundleresources/app-privacy-configuration/nsprivacyaccessedapitypes/nsprivacyaccessedapitype).
