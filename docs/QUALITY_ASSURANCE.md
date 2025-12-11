# Quality Assurance Guide

This project uses a **complementary approach** between pre-commit hooks
  and GitHub Actions CI:

## :bookmark_tabs: Table of Contents

- [:mag: Overview](#overview)
  - [:zap: Pre-commit Hooks](#zap-pre-commit-hooks)
  - [:building_construction: GitHub Actions CI](#building_construction-github-actions-ci)
- [:zap: Pre-commit Hooks](#pre-commit-hooks)
  - [What They Check (Fast & Local)](#what-they-check-fast--local)
  - [Configuration](#configuration)
- [:building_construction: GitHub Actions CI](#github-actions-ci)
  - [What It Checks (Targeted & Remote)](#what-it-checks-targeted--remote)
  - [Configuration](#configuration-1)
- [:arrows_clockwise: Development Workflow](#development-workflow)
  - [Daily Development](#daily-development)
  - [Before Creating a PR](#before-creating-a-pr)
  - [CI Pipeline](#ci-pipeline)
  - [Test Strategy](#test-strategy)
- [:star: Best Practices](#best-practices)
  - [For Developers](#for-developers)
  - [For Maintainers](#for-maintainers)
- [:wrench: Troubleshooting](#troubleshooting)
  - [Pre-commit Issues](#pre-commit-issues)
  - [CI Issues](#ci-issues)
  - [Performance Issues](#performance-issues)
- [:heavy_plus_sign: Adding New Checks](#adding-new-checks)
  - [For Pre-commit (Fast & Local)](#for-pre-commit-fast--local)
  - [For CI (Comprehensive)](#for-ci-comprehensive)
- [:arrows_counterclockwise: Migration Notes](#migration-notes)
  - [From Old Setup](#from-old-setup)

<div id="overview"></div>

## :mag: Overview

### :zap: Pre-commit Hooks
- :white_check_mark: **Speed**: Complete in seconds, not minutes
- :white_check_mark: **Local**: Run on your machine before committing
- :white_check_mark: **Developer-friendly**: Immediate feedback on code quality
- :white_check_mark: **Lightweight**:
Focus on syntax, formatting, and basic checks

### :building_construction: GitHub Actions CI
- :white_check_mark: **Thorough**:
  Full test suite and integration tests
- :white_check_mark: **Remote**:
  Runs on GitHub's infrastructure
- :white_check_mark: **Comprehensive**:
  Data generation, validation, and performance checks
- :white_check_mark: **Reproducible**:
  Ensures consistent results across environments

<div id="pre-commit-hooks"></div>

## :zap: Pre-commit Hooks

### What They Check (Fast & Local)

```bash
# Run manually
pre-commit run --all-files

# Run on specific files
pre-commit run --files scripts/my_script.R
```

**Checks include:**
- :white_check_mark: R code formatting (styler)
- :white_check_mark: R syntax validation
- :white_check_mark: R code linting (lintr)
- :white_check_mark: No debug/browser statements
- :white_check_mark: Spell checking
- :white_check_mark: File formatting (trailing whitespace, EOF)
- :white_check_mark: File size limits
- :white_check_mark: Merge conflict detection

### Configuration
- **File**: `.pre-commit-config.yaml`
- **Speed**: `fail_fast: true` (stops on first error)
- **Scope**: Excludes data/, results/, figures/, logs/ directories

<div id="github-actions-ci"></div>

## :building_construction: GitHub Actions CI

### What It Checks (Targeted & Remote)

**Triggered on:**
- Push to `main` branch
- Pull requests to `main` branch

**Jobs include:**

#### 1. Pre-commit Validation
- Runs the same pre-commit hooks as locally
- Ensures consistency between local and CI environments

#### 2. Project Structure Validation
- Validates required files and directories exist
- Ensures project structure integrity

#### 3. SeqKit Specification Validation
- Validates SeqKit subsampling specifications
- Ensures data generation command consistency

#### 4. Code Quality
- Code formatting and linting verification
- Project structure validation

### Configuration
- **File**: `.github/workflows/ci.yaml`
- **Environment**: Ubuntu latest with Pixi
- **Scope**: Fast validation and basic functionality
- **Exclusions**: Heavy tests run locally on HPC

<div id="development-workflow"></div>

## :arrows_clockwise: Development Workflow

### Daily Development

```bash
# 1. Make changes to your code
# 2. Pre-commit hooks run automatically on commit
git add .
git commit -m "Your commit message"
# Pre-commit hooks run here automatically

# 3. Push to trigger CI
git push origin your-branch
```

### Before Creating a PR

```bash
# Run comprehensive local checks
pre-commit run --all-files  # Includes linting and formatting

# Note: Additional tests will be available once pyproject.toml is updated
# test_dataset_validation.R (37 min) runs nightly on HPC
# test_seqkit_subsampling_specs.R runs automatically in CI

# If all pass, create your PR
```

### CI Pipeline

1. **:zap: Pre-commit job** runs first (fast validation)
2. **:building_construction:
Project structure validation** job validates files and directories
3. **:building_construction: SeqKit validation** job validates specifications
4. **:building_construction:
Code quality** job runs formatting and linting checks

### Test Strategy

- **:zap: Local (pre-commit)**:
  Code quality, syntax, formatting
- **:building_construction: CI (GitHub Actions)**:
  `test_seqkit_subsampling_specs.R`, data generation validation
- **:building_construction: Local HPC (nightly)**:
  `test_dataset_validation.R` (37 min runtime)

<div id="best-practices"></div>

## :star: Best Practices

### For Developers

1. **Always run pre-commit locally** before pushing
2. **Fix issues locally** rather than in CI
3. **Use `pixi run` commands** for consistency
4. **Check CI results** before merging PRs

### For Maintainers

1. **Monitor CI performance** and adjust as needed
2. **Add new checks** to appropriate layer (fast vs comprehensive)
3. **Keep pre-commit hooks fast** (< 30 seconds)
4. **Use CI for heavy operations** (data generation, full tests)

<div id="troubleshooting"></div>

## :wrench: Troubleshooting

### Pre-commit Issues

```bash
# Skip pre-commit hooks (emergency only)
git commit --no-verify

# Update pre-commit hooks
pre-commit autoupdate

# Run specific hook
pre-commit run lintr --all-files
```

### CI Issues

```bash
# Check CI logs in GitHub Actions
# Look for specific job failures
# Fix issues locally and push again
```

### Performance Issues

```bash
# If pre-commit is too slow
# 1. Check for large files being processed
# 2. Review exclusions in .pre-commit-config.yaml
# 3. Consider moving heavy checks to CI only
```

<div id="adding-new-checks"></div>

## :heavy_plus_sign: Adding New Checks

### For Pre-commit (Fast & Local)

```yaml
# Add to .pre-commit-config.yaml
- id: your-fast-check
  name: Your Fast Check
  entry: your-command
  language: system
  files: \.(R|r)$
```

### For CI (Comprehensive)

```yaml
# Add to .github/workflows/ci.yaml
- name: Your comprehensive check
  run: |
    pixi shell -- your-comprehensive-command
```

<div id="migration-notes"></div>

## :arrows_counterclockwise: Migration Notes

### From Old Setup

The old setup had:
- :x: Redundant checks between pre-commit and CI
- :x: Heavy data generation in pre-commit
- :x: No clear separation of concerns

The new setup provides:
- :white_check_mark: Fast local feedback
- :white_check_mark: Comprehensive remote validation
- :white_check_mark: Clear separation of concerns
- :white_check_mark: Better developer experience
