#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."

python3 - <<'PY'
from pathlib import Path
import re
import sys
import zipfile

root = Path.cwd()
skills_dir = root / "skills"
dist_dir = root / "dist"

if not skills_dir.is_dir():
    sys.exit("FAIL: skills/ directory not found")

folders = sorted(path for path in skills_dir.iterdir() if path.is_dir())
if not folders:
    sys.exit("FAIL: no skill folders found")

for folder in folders:
    skill_file = folder / "SKILL.md"
    if not skill_file.is_file():
        sys.exit(f"FAIL: {folder.name}: SKILL.md not found")
    text = skill_file.read_text(encoding="utf-8")
    lines = text.splitlines()
    if len(lines) >= 500:
        sys.exit(f"FAIL: {folder.name}: SKILL.md must be under 500 lines (found {len(lines)})")
    if not lines or lines[0].strip() != "---":
        sys.exit(f"FAIL: {folder.name}: missing YAML frontmatter opening delimiter")
    try:
        end = next(i for i in range(1, len(lines)) if lines[i].strip() == "---")
    except StopIteration:
        sys.exit(f"FAIL: {folder.name}: missing YAML frontmatter closing delimiter")

    # Frontmatter uses simple, single-line YAML scalars for these required fields.
    fields = {}
    for line in lines[1:end]:
        match = re.fullmatch(r"([A-Za-z][A-Za-z0-9_-]*):[ \t]*(.*?)[ \t]*", line)
        if match:
            key, value = match.groups()
            if key in fields:
                sys.exit(f"FAIL: {folder.name}: duplicate frontmatter field {key!r}")
            fields[key] = value
    name = fields.get("name", "").strip().strip("\"'")
    description = fields.get("description", "").strip().strip("\"'")
    if name != folder.name:
        sys.exit(f"FAIL: {folder.name}: frontmatter name is {name!r}")
    if not re.fullmatch(r"[a-z0-9]+(?:-[a-z0-9]+)*", name) or len(name) > 64:
        sys.exit(f"FAIL: {folder.name}: invalid skill name {name!r}")
    if not description or len(description) > 1024:
        sys.exit(f"FAIL: {folder.name}: description must be present and at most 1024 characters")
    archive_path = dist_dir / f"{folder.name}.skill"
    if not archive_path.is_file():
        sys.exit(f"FAIL: {folder.name}: dist/{folder.name}.skill not found")
    member = f"{folder.name}/SKILL.md"
    try:
        with zipfile.ZipFile(archive_path) as archive:
            if archive.namelist().count(member) != 1:
                sys.exit(f"FAIL: {folder.name}: {archive_path.relative_to(root)} must contain {member!r} at the archive root")
            expected_skill = skill_file.read_bytes()
            if archive.getinfo(member).file_size != len(expected_skill):
                sys.exit(f"FAIL: {folder.name}: {member} in {archive_path.relative_to(root)} does not match {skill_file.relative_to(root)}")
            archived_skill = archive.read(member)
    except Exception as error:
        sys.exit(f"FAIL: {folder.name}: cannot read {archive_path.relative_to(root)}: {error}")
    if archived_skill != expected_skill:
        sys.exit(f"FAIL: {folder.name}: {member} in {archive_path.relative_to(root)} does not match {skill_file.relative_to(root)}")

print(f"PASS: checked {len(folders)} skill(s)")
PY
