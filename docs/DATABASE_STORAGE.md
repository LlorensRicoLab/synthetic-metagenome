# Database Storage

This document describes how reference databases are organized in this repository.
The structure shown here was used for ChocoPhlAn/HUMAnN validation,
    but can be adapted for other databases.

## :bookmark_tabs: Table of Contents

- [:mag: Overview](#overview)
- [:file_folder: Structure](#structure)
- [:dna: ChocoPhlAn/MetaPhlAn Databases](#chocophlan-metaphlan-databases)
- [:bulb: Rationale](#rationale)
- [:globe_with_meridians: Adapting for Other Databases](#adapting-for-other-databases)
- [:memo: Notes](#notes)

<div id="overview"></div>

## :mag: Overview

This document describes the database storage structure used in this repository
    for ChocoPhlAn and MetaPhlAn databases.
This structure is a **template**
    that can be adapted for UHGG, RefSeq, or other reference catalogs.

**:information_source: Note**:
    The generator itself does not require ChocoPhlAn or HUMAnN.
    It only needs:
- Properly formatted abundance profiles (see [`INPUT_FILE_FORMATS.md`](INPUT_FILE_FORMATS.md))
- Compatible organism mapping files
- MASH screening results

The structure shown here is what was used for validation
    and serves as a worked example.

<div id="structure"></div>

## :file_folder: Structure

```
data/databases/
├── metaphlan/                          # MetaPhlAn taxonomic profiling databases
│   └── vOct22_CHOCOPhlAnSGB_202403/    # Version-specific database
└── humann/                             # HUMAnN functional profiling databases (if needed)
    ├── chocophlan/
    ├── uniref90/
    └── utility_mapping/
```

<div id="chocophlan-metaphlan-databases"></div>

## :dna: ChocoPhlAn/MetaPhlAn Databases (Example Setup)

This section describes the database structure used for validation
    with ChocoPhlAn and MetaPhlAn.
This is provided as a **worked example**,
    you can adapt this structure for other databases.

### :label: Version: `vOct22_CHOCOPhlAnSGB_202403`

**:white_check_mark: Compatibility (for this example setup):**
- **HUMAnN 4.0.0.alpha.1** :check_mark: (used for validation)
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

**:information_source: Note**:
    This database setup is only needed
        if you want to reproduce the exact validation workflow.
    The generator itself does not require HUMAnN or MetaPhlAn,
        it only needs properly formatted input files.

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

<div id="adapting-for-other-databases"></div>

## :globe_with_meridians: Adapting for Other Databases

This structure can be adapted for other reference databases:

### :dna: UHGG

For UHGG, organize databases similarly:
```
data/databases/
└── uhgg/
    └── v2.0/                       # UHGG version
        ├── genomes/                # UHGG genome FASTA files
        └── metadata/               # UHGG metadata files
```

### :dna: RefSeq

For RefSeq, adapt the structure:
```
data/databases/
└── refseq/
    └── release_xxx/                # RefSeq release version
        ├── bacterial/              # Bacterial genomes
        └── archaeal/               # Archaeal genomes (if needed)
```

### :bulb: Key Principles

Regardless of database:
1. **Organize by version**: Keep different database versions separate
2. **Consistent structure**: Maintain similar organization patterns
3. **Metadata**: Include taxonomy/metadata files alongside genomes
4. **Documentation**: Update paths and identifiers in your `.env` file
