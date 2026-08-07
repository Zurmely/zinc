#!/usr/bin/env python3
"""Create GitHub issues from PRODUCT_REVIEW.md."""

from __future__ import annotations

import json
import re
import subprocess
import sys
import time
from pathlib import Path

REPO = "Zurmely/zinc"
REVIEW_PATH = Path(__file__).resolve().parent.parent / "PRODUCT_REVIEW.md"

SEVERITY_LABELS = {
    "P0": {"color": "b60205", "description": "Data loss, security, or broken in shipped builds"},
    "P1": {"color": "d93f0b", "description": "Materially degrades the core loop"},
    "P2": {"color": "fbca04", "description": "Quality, polish, ergonomics, maintainability"},
}

TYPE_LABELS = {
    "Bug": "bug",
    "Enhancement": "enhancement",
    "Refactor": "enhancement",
    "Performance": "enhancement",
}


def run(cmd: list[str], *, input_text: str | None = None) -> subprocess.CompletedProcess[str]:
    return subprocess.run(
        cmd,
        input=input_text,
        text=True,
        capture_output=True,
        check=True,
    )


def ensure_labels() -> None:
    # GitHub App tokens may lack label-create permission; use existing repo labels only.
    pass


def parse_issues(text: str) -> list[dict[str, str]]:
    pattern = re.compile(r"^### (ZINC-\d+)\s*\n\n\*\*(.+?)\*\*\s*\n\n", re.MULTILINE)
    matches = list(pattern.finditer(text))
    issues: list[dict[str, str]] = []

    for index, match in enumerate(matches):
        issue_id = match.group(1)
        title = match.group(2).strip()
        start = match.end()
        end = matches[index + 1].start() if index + 1 < len(matches) else len(text)
        body = text[start:end].strip()
        if body.endswith("---"):
            body = body[:-3].strip()

        meta_match = re.search(
            r"- \*\*Area:\*\* (.+?) · \*\*Type:\*\* (.+?) · \*\*Severity:\*\* (P[012]) · \*\*Effort:\*\* ([SML])",
            body,
        )
        area = meta_match.group(1).strip() if meta_match else "Unknown"
        issue_type = meta_match.group(2).strip() if meta_match else "Enhancement"
        severity = meta_match.group(3).strip() if meta_match else "P2"
        effort = meta_match.group(4).strip() if meta_match else "M"

        depends = re.search(r"· \*\*Depends on:\*\* (.+)$", body, re.MULTILINE)
        depends_on = depends.group(1).strip() if depends else ""

        issues.append(
            {
                "id": issue_id,
                "title": title,
                "area": area,
                "type": issue_type,
                "severity": severity,
                "effort": effort,
                "depends_on": depends_on,
                "body": body,
            }
        )

    return issues


def build_issue_body(issue: dict[str, str]) -> str:
    lines = [
        f"**{issue['id']}** · Reviewed at commit `6177aef` · Source: `PRODUCT_REVIEW.md`",
        "",
        f"- **Area:** {issue['area']}",
        f"- **Type:** {issue['type']}",
        f"- **Severity:** {issue['severity']}",
        f"- **Effort:** {issue['effort']}",
    ]
    if issue["depends_on"]:
        lines.append(f"- **Depends on:** {issue['depends_on']}")
    lines.extend(["", "---", "", issue["body"]])
    return "\n".join(lines)


def existing_issue_titles() -> set[str]:
    result = run(
        [
            "gh",
            "issue",
            "list",
            "--repo",
            REPO,
            "--state",
            "all",
            "--limit",
            "200",
            "--json",
            "title",
        ]
    )
    titles = {item["title"] for item in json.loads(result.stdout)}
    return titles


def create_issue(issue: dict[str, str]) -> str:
    labels = []
    if issue["type"] in TYPE_LABELS:
        labels.append(TYPE_LABELS[issue["type"]])

    title = f"[{issue['severity']}] {issue['id']}: {issue['title']}"
    body = build_issue_body(issue)

    result = run(
        [
            "gh",
            "issue",
            "create",
            "--repo",
            REPO,
            "--title",
            title,
            "--body-file",
            "-",
            *sum([["--label", label] for label in labels], []),
        ] if labels else [
            "gh",
            "issue",
            "create",
            "--repo",
            REPO,
            "--title",
            title,
            "--body-file",
            "-",
        ],
        input_text=body,
    )
    url = result.stdout.strip()
    return url


def main() -> int:
    text = REVIEW_PATH.read_text(encoding="utf-8")
    issues = parse_issues(text)
    if len(issues) != 49:
        print(f"Expected 49 issues, parsed {len(issues)}", file=sys.stderr)
        return 1

    ensure_labels()
    seen_titles = existing_issue_titles()

    created: list[str] = []
    skipped: list[str] = []

    for issue in issues:
        title = f"[{issue['severity']}] {issue['id']}: {issue['title']}"
        if title in seen_titles:
            skipped.append(title)
            continue
        url = create_issue(issue)
        created.append(url)
        print(url)
        time.sleep(0.3)

    print(f"\nCreated: {len(created)}")
    print(f"Skipped (already exist): {len(skipped)}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
