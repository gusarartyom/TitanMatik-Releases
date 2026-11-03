# TitanMatik distribution

The vendor source ZIP is read only. Its executable retains its original name and bytes.
The sales bot stays in its separate private repository.

## Permanent download links

- Full installation: https://github.com/gusarartyom/TitanMatik-Releases/releases/latest/download/TitanMatik_Setup.exe
- Manual update for channel posts: https://github.com/gusarartyom/TitanMatik-Releases/releases/latest/download/TitanMatik_Update.exe

Both names contain the same verified installer. It discovers an existing installation
from registry/shortcuts, preserves settings and license files, and installs the approved
transparent TitanMatik logo as TitanMatik.ico beside HeroWarsBro.exe. Desktop and Start
menu shortcuts reference that permanent path. The desktop has one application shortcut;
old shortcuts targeting that same executable and the old companion update shortcut are
removed after success. Unrelated shortcuts are preserved. Unknown installations require
an explicit install/update choice and, for an update, the existing application folder.
Multiple existing installations require choosing one. A running application must be closed.

The installer backs up existing files and supports controlled failure rollback. It never
launches vendor code during CI. Unexpected shutdown recovery and manual GUI acceptance
on different user systems are outside the automated test coverage.

## Weekly updates

Monday cron `0 1 * * 1` is 06:00 UTC+5. Each check downloads the source anew from the
configured Drive file ID. The ZIP SHA-256 is compared with the latest stable release.
The packaging fingerprint also detects logo/installer changes even when vendor bytes
are unchanged. No new release is created when both match. Source download failures
retain the current release. Main-branch packaging changes also run the release pipeline.

The pipeline safely validates ZIP paths, scans payload and installer with Defender,
compiles with Inno Setup, and tests installation, updates, profile preservation,
shortcut icon/duplicate cleanup, process refusal, backup failures and rollback on a
disposable GitHub-hosted Windows runner. It stages and verifies an anonymous download
before marking a release stable. Previous releases remain available.

The original Drive URL/name are not published in source or release metadata.
The separate customer Drive ZIP can be maintained as a mirror; this repository has no
Drive write credentials and cannot overwrite that mirror by itself.

## Configuration

Repository secrets:
- UPDATE_DRIVE_FILE_ID: original source file ID (existing configuration).
- UPDATE_BOT_TOKEN and UPDATE_ADMIN_CHAT_ID: existing failure notification settings.

Optional variables:
- TITANMATIK_ANNOUNCEMENTS_ENABLED=true and UPDATE_CHANNEL_ID explicitly enable
  automatic channel posts. Otherwise builds publish files without posting to a channel.
- TITANMATIK_PRODUCTION_ENABLED=true permits the separate manual promotion job.
  Main-branch and scheduled builds publish automatically after their checks.

Manual workflow modes remain candidate (private draft), stage (public prerelease),
and promote (publish previously staged exact bytes). Telegram delivery state is stored
in the release body; ambiguous delivery is never automatically retried.

Only standard runners in this public repository are used; no R2, paid runners,
Actions caches, artifact uploads or cross-repository bot tokens are required.
