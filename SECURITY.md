**English** · [Türkçe](SECURITY.tr.md)

# Security Policy

Mahzen is an encryption app; we are grateful to anyone who reports a security vulnerability.

## Supported versions

Only the latest version on the `main` branch is supported.

## Reporting a vulnerability

**Please do not share security vulnerabilities in a public Issue.**

Use GitHub's private reporting feature instead: the **Security** tab of the repository → **Report a vulnerability**. The report is visible only to the project owner.

If possible, include the following in your report:

- A short description of the vulnerability and its impact
- Steps to reproduce (attach a proof of concept if you have one)
- The affected file/function and version (commit)
- Your suggested fix (optional)

## Process

- We aim to respond to reports within **7 days** at the latest.
- Once a confirmed vulnerability has been fixed, it is announced, with credit to you if you wish.
- We ask that you do not share the details until the fix has been released.

## Scope

In scope: encryption and key management (`Sources/MahzenCore`), the vault format, and app behavior that could leak data (temporary files, clipboard, locking).

Out of scope: an attacker who already has local administrator privileges, malware installed on the device through physical access, the user's choice of a weak password, and the unmodified Argon2 reference code under `Sources/CArgon2` (report those to the [P-H-C/phc-winner-argon2](https://github.com/P-H-C/phc-winner-argon2) repository).

Known limitations are listed in the **"Limitations"** section of the README.
