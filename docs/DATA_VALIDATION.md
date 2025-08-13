# Data Validation Framework

This project includes a comprehensive data validation framework
that ensures data integrity at multiple levels:

**:wrench: For testing infrastructure and setup, see [`docs/TESTING.md`](TESTING.md)**


## :bookmark_tabs: Table of Contents

- [:mag: Overview](#overview)
- [:test_tube: Test Execution](#test-execution)
- [:ballot_box_with_check: Validation Rules](#validation-rules)
- [:link: Integration Points](#integration-points)
  - [:computer: Development Workflow](#development-workflow)
  - [:building_construction: CI Pipeline](#ci-pipeline)
- [:technologist: Usage Examples](#usage-examples)
- [:warning: Error Handling](#error-handling)
- [:zap: Performance Considerations](#performance-considerations)
- [:wrench: Troubleshooting](#troubleshooting)
  - [:rotating_light: Common Issues](#common-issues)
  - [:bug: Debug Mode](#debug-mode)
- [:rocket: Future Enhancements](#future-enhancements)

<div id="overview"></div>

## :mag: Overview

The validation framework consists of two main test suites:

### 1. :clipboard: SeqKit Subsampling Specifications
**File:** `tests/test_seqkit_subsampling_specs.R`

Validates the structure and content of SeqKit subsampling specification files
used for generating synthetic datasets.

**Key Features:**
- :white_check_mark: File existence and accessibility checks
- :white_check_mark:
Command format validation (4 parameters: input, seed, read_count, output)
- :white_check_mark: Read count consistency across simulations
- :white_check_mark: Diversity level validation (low, mid, high)
- :white_check_mark: Simulation count validation (5 per diversity level)
- :white_check_mark: Paired-end read consistency
- :white_check_mark: Seed value validation
- :white_check_mark: Input file existence checks
- :zap: **Fast execution**
(~26 seconds - no caching needed for lightweight validation)

**Expected Structure:**
- 4 sampling depths: 10K, 100K, 1M, 10M reads
- 3 diversity levels: low, mid, high
- 5 simulations per diversity level [^1]
- 60 total datasets per sampling depth

### 2. :dna: Synthetic Dataset Validation
**File:** `tests/test_syn_dataset_validation.R`

Validates synthetic datasets (both individual organism-specific and aggregated)
for format, content, and consistency with intelligent caching.

**Key Features:**
- :white_check_mark: File existence and accessibility checks
- :white_check_mark: Gzip integrity validation
- :white_check_mark: FASTQ format validation (4-line structure)
- :white_check_mark: Paired-end consistency (forward/reverse read counts)
- :white_check_mark: Read count accuracy against filename specifications
- :white_check_mark: Filename parsing and metadata extraction
- :white_check_mark: Directory structure validation
- :zap: **Intelligent caching** for performance optimization

**Expected Structure:**
```
data/synthetic/datasets/
├── low_diversity/
│   ├── individual/     # Organism-specific files
│   └── aggregated/     # Combined simulation files
├── mid_diversity/
│   ├── individual/
│   └── aggregated/
└── high_diversity/
    ├── individual/
    └── aggregated/
```

<div id="test-execution"></div>

## :test_tube: Test Execution

### :clipboard: Running SeqKit Subsampling Specifications Validation

```bash
# Run SeqKit subsampling specification tests
Rscript tests/test_seqkit_subsampling_specs.R
```

**Requirements:**
- SeqKit command files in `data/synthetic/generation/syn_specs/`
- Input FASTQ files in `data/synthetic/generation/source_fastq/`

**Performance Note:**
- **Fast execution**: Typically completes in ~26 seconds
- **No caching needed**: Validates small text files, not large FASTQ data
- **Lightweight**: Only checks SeqKit subsampling specifications,
not FASTQ GZipped files

### :dna: Running Synthetic Dataset Validation

```bash
# Run synthetic dataset validation tests
Rscript tests/test_syn_dataset_validation.R
```

**Requirements:**
- Generated datasets in `data/synthetic/datasets/`
- Note: The first run takes approximately 3.5 minutes.
Without intelligent caching, this would take ~37 minutes (10x slower).
Subsequent runs take ~1m thanks to intelligent caching.

**Caching System:**
- **Cache file**: `data/synthetic/datasets/cache/syn_dataset_validation_cache.json`
- **Cached data**: Read counts, format validation results, file timestamps,
file sizes
- **Cache invalidation**: Based on file last modification times
- **Performance**: Only re-validates changed files,
~1m on subsequent runs (confirmed: 37 minutes &rarr; 3.5 minutes &rarr; 1m)

### :rocket: Running All Tests

```bash
# Run all validation tests
Rscript -e 'testthat::test_dir("tests/")'
```

## :ballot_box_with_check: Validation Rules

### :clipboard: SeqKit Subsampling Specification Files

#### File Structure
- :white_check_mark: File exists and is readable
- :white_check_mark: Non-empty file with valid commands
- :white_check_mark: Each line contains exactly 4 space-separated parameters

#### Subsampling Specification Format
```
{input_file} {seed} {read_count} {output_file}
```

#### Content Validation
- :white_check_mark: Input files exist in source_fastq directory
- :white_check_mark: Seeds are positive integers (1-200) [^2]
- :white_check_mark: AGGREGATE read counts match expected sampling depths
- :white_check_mark: Output filenames follow expected format

#### Filename Format
Individual files: `{organism}_{diversity}_{simulation}_{sampling_depth}_{pair}.fastq.gz`

### :dna: FASTQ GZipped Files

#### File-Level Checks
- :white_check_mark: File exists and is readable
- :white_check_mark: File size > 1KB
- :white_check_mark: Valid gzip compression
- :white_check_mark: FASTQ structure (4 lines per read)
- :white_check_mark: Header lines start with @
- :white_check_mark: Separator lines start with +

#### Metadata Validation
- :white_check_mark: Organism identifier format (e.g., ERR10785402)
- :white_check_mark: Diversity level (low, mid, high)
- :white_check_mark: Simulation number (1-5)
- :white_check_mark: Read count matches filename specification
- :white_check_mark: Pair number (1 or 2)

#### Paired-End Consistency
- :white_check_mark: Forward and reverse files exist
- :white_check_mark: Same read count in both files
- :white_check_mark: Consistent organism metadata

<div id="integration-points"></div>

## :link: Integration Points

### 1. :computer: Development Workflow

#### :zap: Local Testing
```bash
# Quick validation (SeqKit only)
pixi run test

# Full validation (all tests)
pixi run test-all
```

#### :crescent_moon: HPC Nightly Validation
```bash
# Run on HPC for comprehensive validation
Rscript tests/test_dataset_validation.R
```

### 2. :building_construction: CI Pipeline

The validation framework is integrated into the GitHub Actions CI pipeline:

```yaml
- name: Run SeqKit validation tests
  run: |
    pixi shell -- Rscript tests/test_seqkit_subsampling_specs.R

- name: Generate test data
  run: |
    cd data/synthetic/generation
    pixi shell -- Rscript gen_syn_specs.R --no-plots --output-dir test_output_ci
```

**Note:** Comprehensive synthetic dataset validation tests are excluded from CI
due to 3.5-minute runtime (first run only - subsequent runs take ~1m).

**Why not in CI?** These tests require access to DVC-tracked FASTQ GZipped files
that are not present in the git repository.
Including them would require:
- Setting up secure DVC remote access in GitHub Actions
- Handling large file transfers (could hit GitHub Actions limits)
- Significantly increasing CI runtime
- Adding complexity for minimal benefit

**Current Strategy:** Keep CI fast and focused on code quality,
while running comprehensive dataset validation locally
or on HPC where the datasets are available.

<div id="usage-examples"></div>

## :technologist: Usage Examples

### 1. :clipboard: Validate SeqKit Subsampling Specifications

```bash
# Run the test file
Rscript tests/test_seqkit_subsampling_specs.R
```

### 2. :dna: Validate Synthetic Datasets

```bash
# Run the test file
Rscript tests/test_syn_dataset_validation.R
```

### 3. :mag: Check Specific Files

```r
# Parse individual filename
metadata <- parse_individual_filename("ERR10785402_high_1_10000000_1.fastq.gz")
print(metadata)
# $organism: "ERR10785402"
# $diversity: "high"
# $simulation: 1
# $sampling_depth: 10000000
# $pair: "1.fastq.gz"

# Parse aggregated filename
metadata <- parse_aggregated_filename("high_1_10000000_1.fastq.gz")
print(metadata)
# $diversity: "high"
# $simulation: 1
# $sampling_depth: 10000000
# $pair: "1.fastq.gz"
```

<div id="error-handling"></div>

## :warning: Error Handling

The validation framework provides detailed error reporting:

```r
# Example error output
test_that("SeqKit files have correct structure", {
  # If validation fails, you'll see:
  # Error: File not found: seqkit_subsampling_specs_1e+04.txt
  # These files are managed by DVC.
  # Run 'dvc pull data/synthetic/generation/syn_specs.dvc'
  # to download them before running these tests.
})
```

<div id="performance-considerations"></div>

## :zap: Performance Considerations

- **SeqKit validation**: Fast (~26 seconds total)
- **Synthetic dataset validation**: Comprehensive with intelligent caching
  - **First run**: ~3.5 minutes (creates cache)
  - **Normal operation**: ~1 minute (uses validated cached results)
  - **Partial cache updates**:
  ~1-3 minutes (updates cache with new and modified files)
  - **Complete cache regeneration**: ~3.5 minutes (when needed)
  - **Without caching**: ~37 minutes (10x slower)
- **Large file handling**: Uses sampling for files > 1MB
- **Parallel processing**: Uses `mclapply` for FASTQ validation

### :gear: Cache Behavior

The validation framework uses an optimized caching strategy:

- **Files modified but already in cache**:
Don't trigger complete cache regeneration
- **Missing cached files on disk**:
Require user manual intervention (clear error messages)
- **Partial validation**: Only re-validates changed files for faster updates

<div id="troubleshooting"></div>

## :wrench: Troubleshooting

<div id="common-issues"></div>

### :rotating_light: Common Issues

- **Missing SeqKit Subsampling Specification files**
   ```bash
   # Download from DVC
   dvc pull data/synthetic/generation/syn_specs.dvc
   ```

- **Missing datasets**
   ```bash
   # Download from DVC (if available)
   dvc pull data/synthetic/datasets.dvc

   # If datasets don't exist, generate them (takes time)
   cd data/synthetic/generation
   Rscript gen_syn_specs.R --output-dir=syn_specs/
   ./slurm/jobs/submit_seqkit_jobs.sh
   ./scripts/gen_agg_syn_datasets.sh
   ```

- **Permission issues**
   ```bash
   # Check file permissions
   ls -la data/synthetic/datasets/
   ```

<div id="debug-mode"></div>

### :bug: Debug Mode

Enable verbose output for debugging:

```r
# In R, set debug mode
options(testthat.output_file = "validation_debug.log")
```

<div id="future-enhancements"></div>

## :rocket: Future Enhancements

- [ ] **Custom validation schemas** for different file types
  - Extend validation framework to support different file formats (FASTA, SAM, BAM)
  - Allow custom validation rules per file type
  - Implement plugin system for new validation schemas

[^1]: Note that the number of simulations per diversity level can be changed
using the `--sims-per-diversity` argument in [gen_syn_specs.R](../data/synthetic/generation/gen_syn_specs.R).
[^2]: Note that this range can be changed in [gen_syn_specs.R](../data/synthetic/generation/gen_syn_specs.R).
