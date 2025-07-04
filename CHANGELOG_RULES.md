# 📄 CHANGELOG RULES v1.1.0

## 🧭 PURPOSE

Maintain a **human-readable**, **structured**, and **chronological** changelog.  
Do **not** dump raw git logs.  
Follow:
- [Keep a Changelog](https://keepachangelog.com/en/1.1.0/)
- [Semantic Versioning](https://semver.org)

---

## 🏷️ FILE NAMING

- File name: `CHANGELOG.md`
- Format: Markdown
- Date format: `YYYY-MM-DD` (ISO 8601)

---

## 📐 STRUCTURE

Each version entry should follow this structure:

```markdown
## [version_number] - YYYY-MM-DD

### Added
- New features

### Changed
- Changes in existing functionality

### Deprecated
- Soon-to-be removed features

### Removed
- Features that are now removed

### Fixed
- Bug fixes

### Security
- Vulnerabilities and patches
```

Omit any section that has no entries.

---

## 🔄 UNRELEASED SECTION

Always include an `## [Unreleased]` section at the top.

Collect changes here before they are released.

On release, move items from Unreleased to the new version section.

---

## 📌 VERSIONING RULES

Follow Semantic Versioning: `MAJOR.MINOR.PATCH`

| Type    | When to bump |
|---------|-------------|
| MAJOR   | Breaking changes |
| MINOR   | Backward-compatible new features |
| PATCH   | Bug fixes |

---

## ✍️ FORMATTING RULES

- Display newest version at the top.
- Use this header format: `## [version] - YYYY-MM-DD`
- Group changes using subheadings (`### Added`, `### Fixed`, etc.)
- Use consistent bullet list style: `- Item`
- Link version headers to Git diff tags at bottom of file.

---

## 🔗 VERSION LINKING

At the bottom of CHANGELOG.md, include version diff links:

```markdown
[Unreleased]: https://github.com/your-org/repo/compare/v1.1.1...HEAD
[1.1.1]: https://github.com/your-org/repo/compare/v1.1.0...v1.1.1
[1.1.0]: https://github.com/your-org/repo/compare/v1.0.0...v1.1.0
```

---

## ❌ BAD PRACTICES (ANTIPATTERNS)

Avoid:

- Dumping raw git log into changelog
- Ignoring deprecated or removed features
- Mixing inconsistent date formats
- Leaving empty sections
- Hosting changelog only in GitHub Releases

---

## ✅ BEST PRACTICES

- Changelogs are written for humans
- Each version has an entry
- Group changes by type
- Show versions in reverse chronological order
- Make breaking changes & removals explicit
- Use `[YANKED]` tag for pulled releases

Example:

```markdown
## [0.0.5] - 2014-12-13 [YANKED]
```