# Repository guide

This repository contains downloadable Claude skills, not a server application.

## Commands

Run the check from the repository root. It runs offline and requires Bash and
Python 3 (standard library only).

| Task | Command or instructions |
|---|---|
| Install / sandbox setup | None. No dependencies need to be installed in a sandbox with Bash and Python 3. To install a skill in Claude, follow the [README](README.md#install). |
| Test / lint | `bash scripts/check.sh` validates the skill files and checks that the shipped archives match. There are no separate typecheck or unit-test commands. |
| Build | None. The `.skill` archives in `dist/` are checked in. |
| Start | None. There is no server to start. |

## In a factory sandbox

- Test logins: none. There is no authentication, database, or seed data.
- No environment settings, keys, or outside services are needed.
- The factory runs in PR-only mode. There is no preview, port, or health route.

## Scope and done

For this readiness fix, leave skill content, shipped archives, and check
behavior unchanged. Do not add preview or database infrastructure.

Done means `bash scripts/check.sh` passes and the diff contains only `AGENTS.md`.
