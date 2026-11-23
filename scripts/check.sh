#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."

python3 - <<'PY'
from pathlib import Path
import re
import sys
import zipfile


def unquote(value: str) -> str:
    value = value.strip()
    if len(value) >= 2 and value[0] == value[-1] and value[0] in ("'", '"'):
        return value[1:-1].strip()
    return value


root = Path.cwd()
skills_dir = root / "skills"
dist_dir = root / "dist"
readme_path = root / "README.md"

if not skills_dir.is_dir():
    sys.exit("FAIL: skills/ directory not found")

folders = sorted(path for path in skills_dir.iterdir() if path.is_dir())
if not folders:
    sys.exit("FAIL: no skill folders found")

errors = []
folder_names = {folder.name for folder in folders}

# Check that README.md's ## Skills list matches skills/ folders.
if not readme_path.is_file():
    errors.append("FAIL: README.md: file not found")
else:
    readme_lines = readme_path.read_text(encoding="utf-8").splitlines()
    skills_heading = next(
        (i for i, line in enumerate(readme_lines) if re.fullmatch(r"##[ \t]+Skills[ \t]*", line)),
        None,
    )
    if skills_heading is None:
        errors.append("FAIL: README.md: missing '## Skills' section")
    else:
        section_lines = []
        for line in readme_lines[skills_heading + 1 :]:
            if re.match(r"##[ \t]+", line):
                break
            section_lines.append(line)

        table_lines = [line.strip() for line in section_lines if line.strip().startswith("|")]
        sep_idx = next(
            (i for i, line in enumerate(table_lines) if re.fullmatch(r"\|(?:[ \t]*:?-+:?[ \t]*\|)+", line)),
            None,
        )
        if sep_idx is None:
            errors.append("FAIL: README.md: missing skills table in '## Skills' section")
        else:
            readme_skills = set()
            data_rows = table_lines[sep_idx + 1 :]
            if not data_rows:
                errors.append("FAIL: README.md: no skills listed in '## Skills' table")
            for row in data_rows:
                cells = [cell.strip() for cell in row.strip("|").split("|")]
                matches = re.findall(r"\((?:\./)?dist/([^/\s)]+)\.skill\)", row)
                if not matches:
                    label = cells[0] if cells and cells[0] else row
                    errors.append(f"FAIL: {label}: listed in README.md without a dist/<skill>.skill download link")
                elif len(matches) > 1:
                    label = cells[0] if cells and cells[0] else matches[0]
                    errors.append(f"FAIL: {label}: README.md row references multiple skill archives: {', '.join(matches)}")
                else:
                    skill_name = matches[0]
                    if skill_name in readme_skills:
                        errors.append(f"FAIL: {skill_name}: listed more than once in README.md")
                    readme_skills.add(skill_name)

            for skill_name in sorted(folder_names - readme_skills):
                errors.append(f"FAIL: {skill_name}: skill folder in skills/ is missing from README.md")
            for skill_name in sorted(readme_skills - folder_names):
                errors.append(f"FAIL: {skill_name}: listed in README.md but no folder found in skills/")

for folder in folders:
    skill_file = folder / "SKILL.md"
    if not skill_file.is_file():
        errors.append(f"FAIL: {folder.name}: SKILL.md not found")
        continue
    text = skill_file.read_text(encoding="utf-8")
    lines = text.splitlines()
    if len(lines) >= 500:
        errors.append(f"FAIL: {folder.name}: SKILL.md must be under 500 lines (found {len(lines)})")
    if not lines or lines[0].strip() != "---":
        errors.append(f"FAIL: {folder.name}: missing YAML frontmatter opening delimiter")
    else:
        end = next((i for i in range(1, len(lines)) if lines[i].strip() == "---"), None)
        if end is None:
            errors.append(f"FAIL: {folder.name}: missing YAML frontmatter closing delimiter")
        else:
            # Frontmatter uses simple, single-line YAML scalars for these required fields.
            fields = {}
            for line in lines[1:end]:
                match = re.fullmatch(r"([A-Za-z][A-Za-z0-9_-]*):[ \t]*(.*?)[ \t]*", line)
                if match:
                    key, value = match.groups()
                    if key in fields:
                        errors.append(f"FAIL: {folder.name}: duplicate frontmatter field {key!r}")
                    else:
                        fields[key] = value
            name = unquote(fields.get("name", ""))
            description = unquote(fields.get("description", ""))
            if not name:
                errors.append(f"FAIL: {folder.name}: missing frontmatter 'name'")
            else:
                if name != folder.name:
                    errors.append(
                        f"FAIL: {folder.name}: frontmatter name {name!r} does not match folder name {folder.name!r}"
                    )
                if not re.fullmatch(r"[a-z0-9]+(?:-[a-z0-9]+)*", name) or len(name) > 64:
                    errors.append(f"FAIL: {folder.name}: invalid skill name {name!r}")
            if not description:
                errors.append(f"FAIL: {folder.name}: missing frontmatter 'description'")
            elif len(description) > 1024:
                errors.append(
                    f"FAIL: {folder.name}: frontmatter 'description' must be at most 1024 characters (found {len(description)})"
                )

    archive_path = dist_dir / f"{folder.name}.skill"
    if not archive_path.is_file():
        errors.append(f"FAIL: {folder.name}: dist/{folder.name}.skill not found")
        continue
    member = f"{folder.name}/SKILL.md"
    try:
        with zipfile.ZipFile(archive_path) as archive:
            if archive.namelist().count(member) != 1:
                errors.append(
                    f"FAIL: {folder.name}: {archive_path.relative_to(root)} must contain {member!r} at the archive root"
                )
                continue
            expected_skill = skill_file.read_bytes()
            if archive.getinfo(member).file_size != len(expected_skill):
                errors.append(
                    f"FAIL: {folder.name}: {member} in {archive_path.relative_to(root)} does not match {skill_file.relative_to(root)}"
                )
                continue
            archived_skill = archive.read(member)
    except Exception as error:
        errors.append(f"FAIL: {folder.name}: cannot read {archive_path.relative_to(root)}: {error}")
        continue
    if archived_skill != expected_skill:
        errors.append(
            f"FAIL: {folder.name}: {member} in {archive_path.relative_to(root)} does not match {skill_file.relative_to(root)}"
        )

if errors:
    for error in errors:
        print(error, file=sys.stderr)
    sys.exit(1)

print(f"PASS: checked {len(folders)} skill(s)")
PY
