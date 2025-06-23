# Pipeline Benchmarking Project

A comprehensive benchmarking framework for evaluating metatranscriptome analysis pipelines using synthetic datasets.

## Project Overview

This project aims to systematically evaluate and compare different metatranscriptome analysis pipelines (HUMAnN3, Kraken2/Bracken, SAMSA2, RealMap, VicWlad) using carefully designed synthetic datasets with varying diversity levels.

## Project Structure

```
pipeline_benchmarking/
├── data/                         # Data management
│   ├── real/                     # Real metatranscriptome datasets
│   ├── reference/                # Reference databases and genomes
│   │   └── refseq/               # RefSeq bacterial genomes
│   └── synthetic/                # Synthetic datasets
│       ├── datasets/             # Generated synthetic datasets
│       │   ├── high_diversity/   # High diversity communities
│       │   ├── low_diversity/    # Low diversity communities
│       │   └── mid_diversity/    # Medium diversity communities
│       ├── generation/           # Scripts for synthetic data generation
│       │   ├── abundance/        # Abundance profiles
│       │   └── syn_output/       # Generation outputs
│       └── metadata/             # Metadata for synthetic datasets
├── evaluation/                   # Evaluation and analysis
│   ├── notebooks/                # Jupyter notebooks for analysis
│   ├── reports/                  # Evaluation reports
│   └── scripts/                  # Evaluation scripts
├── pipelines/                    # Pipeline implementations
│   ├── humann3/                  # HUMAnN3 pipeline
│   │   ├── config/               # Pipeline configuration
│   │   ├── scripts/              # Pipeline scripts
│   │   └── utils/                # Utility functions
│   └── [other_pipelines]/        # Additional pipelines
├── results/                      # Results and outputs
│   ├── evaluations/              # Evaluation results
│   ├── logs/                     # Pipeline execution logs
│   └── pipeline_outputs/         # Pipeline-specific outputs
├── shared/                       # Shared resources
│   ├── config/                   # Shared configuration files
│   ├── scripts/                  # Shared utility scripts
│   └── utils/                    # Shared utility functions
└── slurm/                        # HPC job management
    ├── config/                   # SLURM configuration
    ├── jobs/                     # Job submission scripts
    ├── logs/                     # SLURM job logs
    └── utils/                    # SLURM utilities
```

## Environment Setup

This project uses Pixi for environment management. To set up the environment:

```bash
pixi install
pixi shell
```

## Dependencies

- R >= 4.4
- tidyverse
- ggpubr
- vegan
- pandoc

## License

MIT License - see LICENSE file for details.

## Authors

- Francisco Merino-Casallo (fmerino at cipf.es)
- Verónica Llorens Rico (vllorens at cipf.es)
