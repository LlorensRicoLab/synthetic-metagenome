# Synthetic Metagenome Generator

A toolkit for generating controlled synthetic metagenome datasets
   with known organism compositions, abundances, and diversity levels.
This generator creates realistic FASTQ files.

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

This toolkit generates synthetic metagenome datasets by:

- **Controlled organism composition**:
   Define exact organism abundances and diversity levels
- **Realistic sequencing simulation**:
   Uses real FASTQ reads from reference organisms
- **Flexible configuration**:
   Supports multiple ecological states, diversity levels, and sampling depths
- **Database-agnostic design**:
   Works with any reference database that provides compatible input formats

**:information_source: Note**:
   This generator has been validated using ChocoPhlAn/HUMAnN reference databases,
      but it is designed to work with any reference database (UHGG, RefSeq, etc.)
      that provides properly formatted abundance profiles, organism mappings,
      and MASH screening results.
   See the [documentation](docs/DATABASE_STORAGE.md)
      for details on adapting to other databases.

<div id="quick-start"></div>

## :rocket: Quick Start

### :pushpin: Prerequisites

- **Linux/Unix system** (tested on CentOS 7+)

### :package: Installation

**1. Clone the repository**:
   ```bash
   git clone <repository-url>
   cd synthetic-metagenome
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
synthetic-metagenome/
├── bin/                                     # Main generation scripts
│   └── gen_syn_specs.R                      # Core synthetic spec generator
├── lib/                                     # Shared libraries
│   ├── R/                                   # R utility functions
│   │   └── verbosity.R                      # Logging utilities
│   └── sh/                                  # Shell utility functions
│       └── logging.sh                       # Shell logging utilities
├── tools/                                   # Helper tools
│   ├── build_mash_mapping.R                 # Build MASH organism mapping
│   ├── gen_agg_syn_datasets.sh              # Aggregate synthetic datasets
│   ├── gen_syn_samples.sh                   # Generate synthetic samples
│   ├── run_mash_pipeline.sh                 # Run MASH screening pipeline
│   ├── subsample_large_fastq.sh             # Subsample large FASTQ files
│   └── verify_aggregated_read_counts.sh     # Verify read counts
├── scripts/                                 # Additional scripts
│   ├── gen_agg_syn_datasets.sh              # Aggregate synthetic datasets
│   ├── subsample_large_fastq.sh             # Subsample large FASTQ files
│   └── verify_aggregated_read_counts.sh     # Verify read counts
├── data/                                    # Data directories
│   ├── abundance/                           # Abundance profile files
│   ├── cache/                               # Cached read counts (.gitkeep)
│   ├── databases/                           # Reference databases (.gitkeep)
│   ├── datasets/                            # Generated datasets (.gitkeep)
│   ├── mapping/                             # Organism mapping files
│   │   └── mash_screening/                  # MASH screening results (.gitkeep)
│   ├── source_fastq/                        # Source FASTQ files (.gitkeep)
│   └── syn_specs/                           # Generation specifications (.gitkeep)
├── docs/                                    # Documentation
│   ├── DATABASE_STORAGE.md                  # Database storage guide
│   ├── DATA_VALIDATION.md                   # Data validation framework
│   ├── ENVIRONMENT_SYNC.md                  # Environment management
│   ├── INPUT_FILE_FORMATS.md                # Input file format specifications
│   ├── MASH_ORGANISM_MAPPING.md             # MASH-based organism mapping
│   ├── QUALITY_ASSURANCE.md                 # Quality assurance framework
│   ├── REFACTORING_SUMMARY.md               # Technical refactoring details
│   ├── SYNTHETIC_DATA_GENERATION.md         # Synthetic data generation guide
│   └── TESTING.md                           # Testing infrastructure
├── slurm/                                   # HPC job management
│   └── jobs/                                # SLURM job scripts
│       └── submit_gen_syn_samples.sh        # Submit generation jobs
├── inst/                                    # Package installation files
│   └── WORDLIST                             # Spell checking wordlist
├── tests/                                   # Test suite
│   ├── test_seqkit_subsampling_specs.R      # SeqKit specs validation
│   └── test_syn_dataset_validation.R        # Dataset validation
└── renv/                                    # R environment management
```

<div id="usage"></div>

## :technologist: Usage

### :dna: Synthetic Data Generation

Generate synthetic datasets using the main generator script:

```bash
# Activate the environment
pixi shell

# Run the generator (generates all diversity levels)
pixi run Rscript bin/gen_syn_specs.R

# Or with custom options
pixi run Rscript bin/gen_syn_specs.R --help
```

**:information_source: Note**:
   The script supports command-line arguments for customization.
See [`docs/SYNTHETIC_DATA_GENERATION.md`](docs/SYNTHETIC_DATA_GENERATION.md)
   for detailed usage options.

### :dna: MASH Organism Mapping

Before generating synthetic datasets, you may need to create organism mappings
   using MASH screening:

```bash
# Set up environment file
cp env.template .env
# Edit .env to set CHOCOPHLAN_DB (or your reference database path)

# Run MASH pipeline
pixi run bash tools/run_mash_pipeline.sh
```

See [`docs/MASH_ORGANISM_MAPPING.md`](docs/MASH_ORGANISM_MAPPING.md) for details.

### :test_tube: Testing

This project includes comprehensive testing and code quality infrastructure:

#### Quick Testing

```bash
# Activate the environment
pixi shell

# Generate synthetic datasets first (required for tests)
pixi run Rscript bin/gen_syn_specs.R --no-plots

# Run SeqKit subsampling specification tests
pixi run Rscript tests/test_seqkit_subsampling_specs.R

# Run all code quality checks
pre-commit run --all-files
```

#### Testing Infrastructure

- **Automated Testing**:
   Pre-commit hooks run automatically before each commit
- **CI/CD Pipeline**:
   GitHub Actions validates code quality on every push and pull request
- **Custom Tests**:
   SeqKit subsampling specification validation ensures data generation reliability

**:book: For detailed testing documentation, see [docs/TESTING.md](docs/TESTING.md)**

<div id="development"></div>

## :construction: Development

### :building_construction: Setting Up Development Environment

If you plan to contribute to this project,
   you'll need to set up additional development tools:

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

### :heavy_plus_sign: Using Other Reference Databases

This generator has been validated with ChocoPhlAn/HUMAnN,
   but can work with other reference databases (UHGG, RefSeq, etc.).
To adapt:

1. Prepare abundance profiles in the format described in [`docs/INPUT_FILE_FORMATS.md`](docs/INPUT_FILE_FORMATS.md)
2. Create organism mapping files compatible with your reference database
3. Run MASH screening against your reference database (see [`docs/MASH_ORGANISM_MAPPING.md`](docs/MASH_ORGANISM_MAPPING.md))
4. Adapt file paths and taxonomy mappings as needed

See the [documentation](docs/DATABASE_STORAGE.md)
   for details on database-agnostic usage.

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

- Check the documentation in `docs/`
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

If you use this synthetic metagenome generator in your research,
   please cite:

```bibtex
@software{synthetic_metagenome_generator,
  title={Synthetic Metagenome Generator: A Toolkit for Controlled Dataset Generation},
  author={Merino-Casallo, Francisco and Llorens Rico, Verónica},
  year={2025},
  url={https://github.com/LlorensRicoLab/synthetic-metagenome}
}
```
