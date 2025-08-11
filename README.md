# Pipeline Benchmarking Project

A comprehensive benchmarking framework for evaluating metatranscriptome analysis pipelines using synthetic datasets.

## :bookmark_tabs: Table of Contents

- [:mag: Project Overview](#project-overview)
- [:rocket: Quick Start](#quick-start)
- [:hammer_and_wrench: Environment Setup](#environment-setup)
- [:file_folder: Project Structure](#project-structure)
- [:technologist: Usage](#usage)
- [:construction: Development](#development)
- [:wrench: Troubleshooting](#troubleshooting)
- [:page_with_curl: License](#license)
- [:busts_in_silhouette: Authors](#authors)
- [:memo: Citation](#citation)

<div id="project-overview"></div>

## :mag: Project Overview

This project aims to systematically evaluate and compare different metatranscriptome analysis pipelines (HUMAnN3, Kraken2/Bracken, SAMSA2, RealMap, VicWlad) using carefully designed synthetic datasets with varying diversity levels.

<div id="quick-start"></div>

## :rocket: Quick Start

### :pushpin: Prerequisites

- **Linux/Unix system** (tested on CentOS 7+)

### :package: Installation

**1. Clone the repository**:
   ```bash
   git clone git@github.com:LlorensRicoLab/pipeline-benchmarking.git
   cd pipeline-benchmarking
   ```

**2. Set up the environment**:
   ```bash
   # Install Pixi if not already installed
   curl -fsSL https://pixi.sh/install.sh | bash

   # Install project dependencies
   pixi install

   # Activate the environment
   pixi shell
   ```

**3. Verify installation**:
   ```bash
   # Check pixi environment
   pixi list

   # Check R environment
   Rscript -e "sessionInfo()"
   ```

### :calendar: Daily Usage

#### Starting Work
```bash
# Activate environment
pixi shell

# Start R
R
```

#### Running Scripts
```bash
# Activate pixi environment
pixi shell

# Run R scripts
Rscript scripts/your_script.R

# Or use pixi run
pixi run Rscript scripts/your_script.R
```

#### Managing Dependencies

**Adding New R Packages:**
```bash
# Edit pyproject.toml and add to [tool.pixi.dependencies] section
pixi add r-new_package

# Or add multiple packages
pixi add r-package1 r-package2
```

**Adding New System Dependencies:**
```bash
# Edit pyproject.toml and add to [tool.pixi.dependencies] section
pixi add new_tool

# Install
pixi install
```

**Updating Dependencies:**
```bash
# Update all packages
pixi update
```

<div id="environment-setup"></div>

## :hammer_and_wrench: Environment Setup

This project uses **Pixi** for comprehensive dependency management, providing:
- **R interpreter** (version 4.4) and R packages
- **System tools** (pandoc, dvc, pre-commit)
- **Cross-platform compatibility**
- **HPC environment compatibility**
- **Research reproducibility**

### :question: Why Pixi?

Pixi handles everything automatically:
- R interpreter and packages (tidyverse, ggpubr, vegan, testthat, etc.)
- System tools and dependencies
- Reproducible environments across different systems
- HPC environment compatibility
- Research reproducibility

### :chains: Core Dependencies
- **R >= 4.4** - Statistical computing and graphics
- **tidyverse** - Data manipulation and visualization
- **ggpubr** - Publication-ready plots
- **vegan** - Community ecology analysis
- **pandoc** - Document conversion

<div id="project-structure"></div>

## :file_folder: Project Structure

```
pipeline_benchmarking/
├── data/                                   # Data management
│   ├── real/                               # Real metatranscriptome datasets
│   ├── reference/                          # Reference databases and genomes
│   │   └── refseq/                         # RefSeq bacterial genomes
│   └── synthetic/                          # Synthetic datasets
│       ├── datasets/                       # Generated synthetic datasets (DVC-tracked)
│       │   ├── high_diversity/             # High diversity communities
│       │   ├── low_diversity/              # Low diversity communities
│       │   └── mid_diversity/              # Medium diversity communities
│       └── generation/                     # Synthetic data generation
│           ├── abundance/                  # Abundance profiles
│           ├── cache/                      # Cached read counts
│           ├── mapping/                    # Organism mapping files
│           ├── source_fastq/               # Source FASTQ files (DVC-tracked)
│           └── syn_specs/                  # Generated specifications (DVC-tracked)
├── docs/                                   # Documentation
│   ├── QUALITY_ASSURANCE.md                 # Quality assurance framework
│   ├── DATA_VALIDATION.md                  # Data validation framework
│   ├── REFACTORING_SUMMARY.md              # Technical refactoring details
│   ├── SYNTHETIC_DATA_GENERATION.md        # Synthetic data generation guide
│   └── TESTING.md                          # Testing infrastructure and setup
├── evaluation/                             # Evaluation and analysis
│   ├── notebooks/                          # Jupyter notebooks for analysis
│   ├── reports/                            # Evaluation reports
│   └── scripts/                            # Evaluation scripts
├── figures/                                # Generated figures and plots
├── logs/                                   # Application logs
├── pipelines/                              # Pipeline implementations
│   └── humann3/                            # HUMAnN3 pipeline
│       ├── config/                         # Pipeline configuration
│       ├── scripts/                        # Pipeline scripts
│       └── utils/                          # Utility functions
├── results/                                # Results and outputs
│   ├── evaluations/                        # Evaluation results
│   └── logs/                               # Pipeline execution logs
├── scripts/                                # Utility scripts
│   ├── gen_agg_syn_datasets.sh             # Generate aggregated datasets
│   ├── subsample_large_fastq.sh            # Subsample large FASTQ files
│   └── verify_aggregated_read_counts.sh    # Verify read counts
├── slurm/                                  # HPC job management
│   ├── config/                             # SLURM configuration
│   ├── jobs/                               # Job submission scripts
│   ├── logs/                               # SLURM job logs
│   └── utils/                              # SLURM utilities
└── tests/                                  # Test suite
    ├── test_seqkit_subsampling_specs.R     # SeqKit specs validation
    └── test_syn_dataset_validation.R       # Dataset validation
```

<div id="usage"></div>

## :technologist: Usage

### :dna: Synthetic Data Generation

Generate synthetic datasets using the original R scripts:

```bash
# Activate the environment
pixi shell

# Navigate to generation directory
cd data/synthetic/generation

# Run the simulation script (generates all diversity levels)
Rscript gen_syn_specs.R
```

**Note**: The script supports command-line arguments for customization.
See [`docs/SYNTHETIC_DATA_GENERATION.md`](docs/SYNTHETIC_DATA_GENERATION.md)
for detailed usage options.

### :test_tube: Testing

This project includes comprehensive testing and code quality infrastructure:

#### Quick Testing

```bash
# Activate the environment
pixi shell

# Generate synthetic datasets first (required for tests)
Rscript data/synthetic/generation/gen_syn_specs.R --no-plots

# Run SeqKit subsampling specification tests
Rscript tests/test_seqkit_subsampling_specs.R

# Run all code quality checks
pre-commit run --all-files
```

#### Testing Infrastructure

- **Automated Testing**: Pre-commit hooks run automatically before each commit
- **CI/CD Pipeline**:
GitHub Actions validates code quality on every push and pull request
- **Custom Tests**:
SeqKit subsampling specification validation ensures data generation reliability

**:book: For detailed testing documentation, see [docs/TESTING.md](docs/TESTING.md)**

<div id="development"></div>

## :construction: Development

### :building_construction: Setting Up Development Environment

If you plan to contribute to this project, you'll need to set up additional development tools:

```bash
# Activate the environment
pixi shell

# Install pre-commit hooks
pre-commit install
```

### :white_check_mark: Code Quality and Testing

This project uses comprehensive code quality tools and testing infrastructure:

- **Pre-commit Hooks**: Automatic code formatting, linting, and quality checks
- **Custom Tests**: SeqKit command consistency validation
- **CI/CD Pipeline**: Automated testing on GitHub Actions

**:book: For detailed development setup and testing documentation, see [docs/TESTING.md](docs/TESTING.md)**

### :heavy_plus_sign: Adding New Pipelines

1. Create a new directory in `pipelines/`
2. Add configuration files in `config/`
3. Create execution scripts in `scripts/`
4. Add utility functions in `utils/`
5. Update evaluation scripts to include the new pipeline

### :handshake: Contributing

1. Fork the repository
2. Create a feature branch: `git checkout -b feature/new-pipeline`
3. Make your changes and commit: `git commit -m "feat: Add new pipeline"`
4. Push to your fork: `git push origin feature/new-pipeline`
5. Create a pull request

<div id="troubleshooting"></div>

## :wrench: Troubleshooting

### :warning: Common Issues

1. **Pixi environment not found**:
   ```bash
   pixi install --force
   pixi shell
   ```

2. **R Package Issues**:
   ```r
   # Check installed packages
   Rscript -e "installed.packages()"

   # Check specific package
   Rscript -e "library(package_name)"
   ```

3. **System Dependency Issues**:
   ```bash
   # Reinstall pixi environment
   pixi install --force

   # Update pixi itself
   pixi self update
   ```

### :star: Best Practices

1. **Always use pixi shell** before running R scripts
**or use pixi run** for direct execution
2. **Commit pixi.lock** to version control for reproducibility
3. **Use pixi add** for new dependencies
4. **Update pyproject.toml** for dependency changes
5. **Test on clean environment** before major releases

### :sos: Getting Help

- Check the logs in `results/logs/`
- Review pipeline-specific documentation
- Open an issue on GitHub with detailed error information

<div id="license"></div>

## :page_with_curl: License

MIT License - see [LICENSE](LICENSE) file for details.

<div id="authors"></div>

## :busts_in_silhouette: Authors

- Francisco Merino-Casallo (fmerino at cipf.es)
- Verónica Llorens Rico (vllorens at cipf.es)

<div id="citation"></div>

## :memo: Citation

If you use this benchmarking framework in your research, please cite:

```bibtex
@software{pipeline_benchmarking,
  title={Pipeline Benchmarking: A Framework for Metatranscriptome Analysis},
  author={Merino-Casallo, Francisco and Llorens Rico, Verónica},
  year={2025},
  url={https://github.com/LlorensRicoLab/pipeline-benchmarking}
}
```
