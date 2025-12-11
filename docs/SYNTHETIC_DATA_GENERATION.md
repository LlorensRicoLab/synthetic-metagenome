# :dna: Synthetic Dataset Generation

This directory contains the workflow
  for generating synthetic metatranscriptome datasets
  with controlled diversity levels.

## :bookmark_tabs: Table of Contents

- [:mag: Overview](#overview)
- [:file_folder: Files](#files)
- [:arrows_clockwise: Workflow](#workflow)
- [:clipboard: Usage](#usage)
  - [:scissors: Pre-processing: Subsample large FASTQ files](#scissors-pre-processing-subsample-large-fastq-files)
  - [:house: Local execution](#house-local-execution)
  - [:houses: SLURM execution](#houses-slurm-execution)
  - [:recycle: Post-processing workflow](#recycle-post-processing-workflow)
- [:chains: Dependencies](#dependencies)

<div id="overview"></div>

## :mag: Overview

The synthetic dataset generation creates controlled datasets
  with known ground truth.
Datasets are generated with three diversity levels:
- **:red_circle: Low diversity** (< 0.5 Simpson index)
- **:yellow_circle: Mid diversity** (0.5 - 0.75 Simpson index)
- **:green_circle: High diversity** (> 0.75 Simpson index)

<div id="files"></div>

## :file_folder: Files

- :robot: `bin/gen_syn_specs.R`:
  Main R script for dataset generation and subsampling specifications
- :link: `data/mapping/run_organism_map.csv`:
  Mapping between SRA runs and bacterial species
- :abacus: `data/abundance/`:
  Directory containing community abundance profiles
- :file_folder: `data/source_fastq/`:
  Directory containing source FASTQ files for subsampling
- :floppy_disk: `data/cache/`:
  Directory for caching available read counts
- :memo: `data/syn_specs/`:
  Output directory for generated dataset specifications

<div id="workflow"></div>

## :arrows_clockwise: Workflow

1. **Data Preparation**:
  Subsample large organism-specific FASTQ GZIP files
    to ensure they don't exceed 10M reads
2. **Data Loading**:
  Load and validate abundance profiles and organism mappings
3. **Specification Generation**:
  Generate synthetic community specifications
    with controlled diversity values and levels, as well as relative abundances
4. **Availability Validation**:
  Validate read availability constraints for each organism
5. **Dataset Specification Generation**:
  Generate subsampling specifications for different read counts
    (10K, 100K, 1M, 10M)
6. **Visualization**:
  Create visualization plots of abundance distributions
7. **Output Generation**:
  Save results and generate SeqKit subsampling specifications
8. **HPC Execution**:
  Execute SLURM jobs to generate organism-specific subsampled FASTQ files
9. **Dataset Aggregation**:
  Generate aggregated synthetic datasets from individual organism files
10. **Dataset Validation**:
  Verify aggregated read counts and validate dataset integrity

<div id="usage"></div>

## :clipboard: Usage

### :scissors: Pre-processing: Subsample large FASTQ files
```bash
bash scripts/subsample_large_fastq.sh
```
**Purpose:** Subsamples organism-specific FASTQ GZIP files
  with more than 10M reads.
Since the maximum sampling depth is 10M,
  there is no need to store organism-specific FASTQ GZIP files
  with more than 10M reads.

### :house: Local execution
```bash
Rscript bin/gen_syn_specs.R --seed 42 --sims-per-ecology 200 --sims-per-diversity 5 --output-dir data/syn_specs/
```

#### Configuration

Command line arguments:
- `--sims-per-ecology`: Number of simulations per ecology state [default: 200]
- `--sims-per-diversity`: Number of simulations per diversity level [default: 5]
- `--output-dir`: Output directory [default: syn_specs/]
- `--seed`: Random seed for reproducibility [default: 42]
- `--no-plots`: Disable plot generation [default: FALSE]

#### Expected output

The script generates:
- :page_facing_up: `data/syn_specs/sims_specs.tsv`:
  Simulations specifications with all metadata
- :clipboard: `data/syn_specs/seqkit_subsampling_specs_*.txt`:
  SeqKit subsampling specifications for each read count
- :bar_chart: `data/syn_specs/plots/`:
  Visualization plots of abundance distributions

### :houses: SLURM execution
```bash
sbatch slurm/jobs/submit_gen_syn_samples.sh
```

#### Expected output

- :dna: Organism-specific subsampled FASTQ GZIP files in `data/datasets/*_diversity/individual/*.fastq.gz`

### :recycle: Post-processing workflow

After SLURM execution completes, run the following scripts:

#### 1. Generate aggregated datasets
```bash
bash scripts/gen_agg_syn_datasets.sh
```
##### Expected output
- Aggregated synthetic simulations in `data/datasets/*_diversity/aggregated/*.fastq.gz`

#### 2. Verify aggregated read counts
```bash
bash scripts/verify_aggregated_read_counts.sh
```
**Purpose:** Validates that aggregated synthetic simulations
  contain the expected number of reads for their sampling depth.

<div id="dependencies"></div>

## :chains: Dependencies

- **R >= 4.4**: Statistical computing and graphics
- **tidyverse**: Data manipulation and visualization
- **ggpubr**: Publication-ready plots
- **optparse**: Command-line argument parsing
- **here**: Project-relative file paths
- **jsonlite**: JSON file handling
- **future**: Parallel processing framework
- **furrr**: Parallel iteration with futures
- **vegan**: Community ecology analysis
- **stringr**: String manipulation
- **khroma**: Color schemes for scientific visualization (installed via renv)
