# Pipeline Benchmarking Project

A comprehensive benchmarking framework for evaluating metatranscriptome analysis pipelines using synthetic datasets.

## Project Overview

This project aims to systematically evaluate and compare different metatranscriptome analysis pipelines (HUMAnN3, Kraken2/Bracken, SAMSA2, RealMap, VicWlad) using carefully designed synthetic datasets with varying diversity levels.

## Quick Start

### Prerequisites

- **Linux/Unix system** (tested on CentOS 7+)

### Installation

1. **Clone the repository**:
   ```bash
   git clone git@github.com:LlorensRicoLab/pipeline-benchmarking.git
   cd pipeline-benchmarking
   ```

2. **Set up the environment**:
   ```bash
   # Install Pixi if not already installed
   curl -fsSL https://pixi.sh/install.sh | bash
   
   # Install project dependencies
   pixi install
   
   # Activate the environment
   pixi shell
   ```

3. **Verify installation**:
   ```bash
   # Check if all dependencies are available
   R --version
   ```

## Environment Setup

This project uses Pixi for environment management. The environment includes:

### Core Dependencies
- **R >= 4.4** - Statistical computing and graphics
- **tidyverse** - Data manipulation and visualization
- **ggpubr** - Publication-ready plots
- **vegan** - Community ecology analysis
- **pandoc** - Document conversion

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

## Usage

### 1. Synthetic Data Generation

Generate synthetic datasets using the original R scripts:

```bash
# Activate the environment
pixi shell

# Navigate to generation directory
cd data/synthetic/generation

# Run the simulation script (generates all diversity levels)
Rscript gen_seqkit_comms.R
```

**Note**: The current scripts generate all diversity levels at once. Command-line argument support will be added in future versions.

## Development

### Adding New Pipelines

1. Create a new directory in `pipelines/`
2. Add configuration files in `config/`
3. Create execution scripts in `scripts/`
4. Add utility functions in `utils/`
5. Update evaluation scripts to include the new pipeline

### Contributing

1. Fork the repository
2. Create a feature branch: `git checkout -b feature/new-pipeline`
3. Make your changes and commit: `git commit -m "feat: Add new pipeline"`
4. Push to your fork: `git push origin feature/new-pipeline`
5. Create a pull request

## Troubleshooting

### Common Issues

1. **Pixi environment not found**:
   ```bash
   pixi install --force
   pixi shell
   ```

### Getting Help

- Check the logs in `results/logs/`
- Review pipeline-specific documentation
- Open an issue on GitHub with detailed error information

## License

MIT License - see LICENSE file for details.

## Authors

- Francisco Merino-Casallo (fmerino at cipf.es)
- Verónica Llorens Rico (vllorens at cipf.es)

## Citation

If you use this benchmarking framework in your research, please cite:

```bibtex
@software{pipeline_benchmarking,
  title={Pipeline Benchmarking: A Framework for Metatranscriptome Analysis},
  author={Merino-Casallo, Francisco and Llorens Rico, Verónica},
  year={2025},
  url={https://github.com/LlorensRicoLab/pipeline-benchmarking}
}
```
