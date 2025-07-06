# Deprecated Feature Memory System

This directory contains the old Feature Memory system documentation that has been replaced by the Integrated Development Memory (IDM) system.

## Migration Notice

The old markdown-based Feature Memory system has been replaced with a code-integrated Ruby DSL system that provides:

- Single source of truth in Ruby classes
- Automatic progress tracking
- Better AI agent integration
- Code-integrated documentation

## New System

Use the new Integrated Development Memory (IDM) system:

```bash
# Generate new feature memory
rails generate feature_memory feature_name "Description"
```

See `/docs/INTEGRATED_DEVELOPMENT_MEMORY.md` for full documentation.

## Migration

To migrate old feature memories:

```bash
rails fm:migrate
```

## Deprecated Files

- `FEATURE_MEMORY_OLD.md` - Old system documentation
- `FEATURE_MEMORY_RULES_OLD.md` - Old usage rules
- `/bin/feature-memory-old` - Old CLI tool
- `/lib/tasks/feature_memory_old.rake` - Old rake tasks

These files are preserved for reference but should not be used for new features.