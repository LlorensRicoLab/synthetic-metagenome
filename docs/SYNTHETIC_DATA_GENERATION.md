# Synthetic Dataset Generation

This directory contains the workflow
for generating synthetic metatranscriptome datasets
with controlled diversity levels for pipeline benchmarking.

## Overview

The synthetic dataset generation creates controlled datasets
with known ground truth
to evaluate the performance of metatranscriptome analysis pipelines.
Datasets are generated with three diversity levels:
- **Low diversity** (< 0.5 Simpson index)
- **Mid diversity** (0.5 - 0.75 Simpson index)
- **High diversity** (> 0.75 Simpson index)

## Files

- `gen_syn_specs.R` - Main R script for dataset generation
and subsampling specifications
- `mapping/run_organism_map.csv` - Mapping between SRA runs
and bacterial species
- `abundance/` - Directory containing community abundance profiles
- `source_fastq/` - Directory containing source FASTQ files for subsampling
- `cache/` - Directory for caching available read counts
- `syn_specs/` - Output directory for generated dataset specifications

## Workflow

1. **Phase 1**: Subsample large organism-specific FASTQ GZIP files
to ensure they don't exceed 10M reads
2. **Phase 2**: Load and validate abundance profiles and organism mappings
3. **Phase 3**: Generate synthetic community specifications
with controlled diversity values and levels, as well as relative abundances
4. **Phase 4**: Validate read availability constraints for each organism
5. **Phase 5**: Generate subsampling commands for different read counts
(10K, 100K, 1M, 10M)
6. **Phase 6**: Create visualization plots of abundance distributions
7. **Phase 7**: Save results and generate SeqKit subsampling specifications
8. **Phase 8**: Execute SLURM jobs
to generate organism-specific subsampled FASTQ files
9. **Phase 9**: Generate aggregated synthetic datasets
from individual organism files
10. **Phase 10**: Verify aggregated read counts and validate dataset integrity

## Usage

### Pre-processing: Subsample large FASTQ files
```bash
scripts/subsample_large_fastq.sh
```
**Purpose:** Subsamples organism-specific FASTQ GZIP files
with more than 10M reads.
Since the maximum sampling depth is 10M,
there is no need to store organism-specific FASTQ GZIP files
with more than 10M reads.

### Local execution
```bash
Rscript data/synthetic/generation/gen_syn_specs.R --seed 42 --sims-per-ecology 200 --sims-per-diversity 5 --output-dir data/synthetic/generation/syn_specs/
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
- `syn_specs/sims_specs.tsv` - Simulations specifications with all metadata
- `syn_specs/seqkit_subsampling_specs_*.txt` - SeqKit subsampling commands
for each read count
- `syn_specs/plots/` - Visualization plots of abundance distributions

### SLURM execution
```bash
sbatch slurm/jobs/submit_seqkit_jobs.sh
```

#### Expected output

- Organism-specific subsampled FASTQ GZIP files in `data/synthetic/datasets/*_diversity/individual/*.fastq.gz`

### Post-processing workflow

After SLURM execution completes, run the following scripts:

1. **Generate aggregated datasets:**
```bash
scripts/gen_agg_syn_datasets.sh
```
#### Expected output
- Aggregated synthetic simulations in `data/synthetic/datasets/*_diversity/aggregated/*.fastq.gz`

2. **Verify aggregated read counts:**
```bash
scripts/verify_aggregated_read_counts.sh
```
**Purpose:** Validates that aggregated synthetic simulations
contain the expected number of reads for their sampling depth.

## Dependencies

- R 4.2.0+
- tidyverse
- ggpubr
- optparse
- here
- jsonlite
- future
- furrr
- vegan
- stringr
