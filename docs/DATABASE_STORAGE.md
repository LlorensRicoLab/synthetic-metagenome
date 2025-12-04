# Database Storage

This directory contains reference databases used by various pipelines in the benchmarking project.

## :bookmark_tabs: Table of Contents

- [:mag: Overview](#overview)
- [:file_folder: Structure](#structure)
- [:dna: MetaPhlAn Databases](#metaphlan-databases)
- [:bulb: Rationale](#rationale)
- [:memo: Notes](#notes)

<div id="overview"></div>

## :mag: Overview

This directory contains reference databases used by various pipelines in the benchmarking project.
Databases are stored in a pipeline-agnostic structure to enable reusability across multiple analysis tools.

<div id="structure"></div>

## :file_folder: Structure

```
data/databases/
├── metaphlan/              # MetaPhlAn taxonomic profiling databases
│   └── vOct22_CHOCOPhlAnSGB_202403/  # Version-specific database
└── humann/                 # HUMAnN functional profiling databases (if needed)
    ├── chocophlan/
    ├── uniref90/
    └── utility_mapping/
```

<div id="metaphlan-databases"></div>

## :dna: MetaPhlAn Databases

### :label: Version: `vOct22_CHOCOPhlAnSGB_202403`

**:white_check_mark: Compatibility:**
- **HUMAnN 4.0.0.alpha.1** :check_mark: (REQUIRED)
- **MetaPhlAn 4.1.1** :check_mark:
- **NOT compatible with MetaPhlAn 4.2+** :x:

**:hammer_and_wrench: Installation:**
```bash
pixi run metaphlan --install \
    --bowtie2db data/databases/metaphlan/vOct22_CHOCOPhlAnSGB_202403 \
    --index mpa_vOct22_CHOCOPhlAnSGB_202403
```

**:link: References:**
- [HUMAnN 4 + MetaPhlAn 4 compatibility](https://forum.biobakery.org/t/metaphlan-4-humann-4-compatibility/8523)
- [Installation guide](https://forum.biobakery.org/t/metaphlan-4-humann-4-compatibility/8523/8)

<div id="rationale"></div>

## :bulb: Rationale

This pipeline-agnostic structure allows:
- **:recycle: Reusability**:
    Database structure can be reused across different reference catalogs
        (ChocoPhlAn, UniRef, RefSeq, etc.), provided they follow the same layout
- **:label: Version management**:
    Clear version-specific directories prevent compatibility issues
- **:link: Consistency**:
    Follows the same organizational pattern
        in both `data/mapping/` and `data/databases/`
- **:book: Self-documentation**:
    Directory structure clearly indicates purpose and versions

<div id="notes"></div>

## :memo: Notes

- :no_entry_sign: Database files are excluded from version control (see `.gitignore`)
- :file_folder: Each database version should have its own subdirectory
- :pencil2: When adding new database versions, update this README with compatibility information
