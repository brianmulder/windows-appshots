# Code signing policy

## Current status

Windows AppShots releases are currently unsigned. Windows may show an unknown-publisher warning.

The release includes a SHA-256 checksum and machine-readable build receipt. GitHub Actions builds and tests the installer from the exact release source.

A checksum can detect changed bytes. It does not provide the publisher identity guarantees of Authenticode. Download releases only from `brianmulder/windows-appshots` and verify the checksum before use.

## Release approval

Brian Mulder is the sole maintainer and release approver. Repository and future signing access require multi-factor authentication.

A release can proceed only after the Windows release workflow passes for its exact source commit and the installer, checksums, and build receipt agree.

## Planned signing

After the first public release, the project will apply for free code signing from [SignPath.io](https://signpath.io/), with a certificate from [SignPath Foundation](https://signpath.org/).

The project has not been accepted and does not currently receive signing services from either organisation.

If accepted, signing will be added to the release workflow with manual approval by Brian. Until then, releases remain clearly labelled as unsigned.

See [PRIVACY.md](PRIVACY.md) for the privacy policy.
