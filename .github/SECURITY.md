# Security policy

Mac Vitals reads the machine and never changes it. It runs as a normal user, with no root, no entitlement, and no helper daemon. The MCP server is read-only. Still, if you find something that looks like a security problem, please tell me before you tell the world.

## Reporting

Email n.satsawat@gmail.com with the details, or open a private advisory through GitHub's "Report a vulnerability" on the Security tab. Please do not open a public issue for a vulnerability.

A useful report says what you found, how to reproduce it, and what an attacker could do with it. I will confirm I received it, work out a fix, and credit you when it ships, unless you would rather stay anonymous.

## Scope worth a closer look

- The private IOReport symbols loaded at runtime from `/usr/lib/libIOReport.dylib`. They are isolated in one file on purpose.
- The AppleSMC read path in the `CSMC` C target.
- Anything the MCP server exposes over stdio.

## Supported versions

This is young and pre-1.0, so fixes land on the latest release and on `main`. There is no back-porting to older tags yet.
