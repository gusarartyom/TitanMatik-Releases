# TitanMatik Releases — no R2 subscription

Distribution and Windows builds run in a separate **public** repository using
standard GitHub-hosted runners. The sales/support bot and its source stay private.
No R2, Workers Paid plan, payment method, larger runners, Actions artifact uploads
or caches are needed. The old R2 update workflow has been removed.

GitHub documents no release bandwidth limit and a 2 GiB limit per asset. Standard
public-repository runners are free. This design avoids download-volume bills;
GitHub may still rate-limit or suspend abuse. Downloads never trigger a workflow.

## Publication

## Client updates

The installer discovers an existing installation from the remembered path or
application shortcuts, skipping the directory picker when exactly one is found.
Multiple candidates require an explicit choice; unidentified old ZIP installations
still require locating the folder once. The installed desktop shortcut for updating
runs a companion script in the application directory. It checks the latest stable
release, skips the installed installer hash, verifies the downloaded SHA-256 and
updates that exact directory with progress, without launching vendor code silently.
It asks the user to close a running application and does not terminate it.
An in-application button requires application source code. No stable release means
the companion updater cannot download an update yet.

Every scheduled or manual build downloads the current ZIP anew from the same
Google Drive file ID through the official Drive API. No GitHub source draft,
checked-in ZIP, previous download or source cache is accepted. The downloaded
content is hashed and compared with the last stable release; an unchanged address
does not mean unchanged content. Replacing the ZIP contents in Drive while keeping
the same file ID is supported. A different file ID requires updating the source
configuration. Download failure stops the run and retains the previous release.

The fresh ZIP is hashed, safely unpacked,
Defender-scanned, compiled with Inno Setup, scanned again and installation-tested.
The vendor executable is never launched in CI. User data is excluded/preserved.

Manual `candidate` creates a draft release with the verified installer, a manifest
and SHA256SUMS. Only maintainers can access drafts. `stage` makes a verified public
prerelease and checks an anonymous full download, without changing the latest stable
release. `promote` takes an existing staged tag, verifies those exact bytes again,
then makes it the latest stable release; it does not rebuild the installer.
Previous releases/assets stay available for rollback.

Permanent link after first successful promotion:
`https://github.com/gusarartyom/TitanMatik-Releases/releases/latest/download/TitanMatik_Setup.exe`

Telegram is announced only after stable promotion. Notification state lives in the
release body, with workflow concurrency preventing overlapping publisher runs.
Ambiguous delivery stops retries and needs a channel check; it never blindly resends.
Administrator errors include a run URL without credentials.

## Required repository configuration

No payment/subscription is required for this design. Do not enable larger runners
or add Actions artifact/cache upload steps. The workflow refuses a private repo.

Actions repository secrets (never commit values or paste them into chat):
- UPDATE_DRIVE_SERVICE_ACCOUNT_JSON: read-only access to the source Drive ZIP.
- UPDATE_DRIVE_FILE_ID: the owner's source ZIP ID; it is not embedded in public code.
- UPDATE_BOT_TOKEN: Telegram bot used for notifications.
- UPDATE_ADMIN_CHAT_ID: administrator's private chat ID.

Repository variables:
- UPDATE_CHANNEL_ID: verified test channel first, production channel only after acceptance.
- TITANMATIK_PRODUCTION_ENABLED: leave unset/false until the real installer and
  test-channel release pass. Setting true permits scheduled stable publications.

The ephemeral GITHUB_TOKEN handles releases inside this repository. No persistent
cross-repository token or access to the private sales-bot repository is required.
The packaging kit contains only an explicit allowlist of installer tooling;
worker.js, bot config, licensing records and secrets are not copied.

Monday cron `0 1 * * 1` means 06:00 Asia/Qostanay. With production enabled, changed
source content is automatically built, staged, checked, promoted and announced.
Unchanged ZIP SHA-256 does not create another release/post. Manual dispatch also
supports candidate, stage and promotion of an exact existing release tag.

## Acceptance still required

Fixture tests cover installation, old-file replacement, user data, process refusal,
real ACL denial, enumeration error, controlled rollback and missing-backup safety.
Actual source access, real installer compatibility, test-channel delivery and the
first real release remain unverified until credentials are configured and run.
Power-loss/forced-termination recovery, GUI and another physical drive need separate
acceptance. Do not switch buyer DOWNLOAD_URL until those release gates are satisfied.

References:
- https://docs.github.com/en/repositories/releasing-projects-on-github/about-releases
- https://docs.github.com/en/billing/concepts/product-billing/github-actions
