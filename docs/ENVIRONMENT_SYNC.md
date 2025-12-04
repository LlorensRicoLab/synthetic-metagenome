# Pixi + renv Coexistence Guide

## :question: Why we run both managers

This approach follows best practices for using R within Conda-based environments (see [References](#references) below).

- [Pixi](https://pixi.sh/latest) supplies the base R 4.4 toolchain plus most [CRAN packages](https://cran.r-project.org/)
    through [conda-forge](https://conda-forge.org/).
- Some packages (e.g. `khroma`)
    are **not** yet available on any active conda channel,
    so we install them with CRAN/renv
    while the upstream conda-forge proposal is pending (see [tesselle/khroma#18](https://codeberg.org/tesselle/khroma/issues/18)).
- `.Rprofile` sources `renv/activate.R` automatically,
    so every `pixi run Rscript …` session loads renv
    on top of Pixi's site library.
    Both managers therefore see each other's packages.

## :warning: What `project is out-of-sync` means
- renv compares the actual packages on `.libPaths()`
    against the versions recorded in `renv.lock`.
- Pixi upgrades (or CRAN installs) make packages appear “installed”
    but “unrecorded”, so renv warns until the lockfile reflects the new state.
- The warning does **not** mean anything is broken;
    it just signals that `renv::snapshot()` or `renv::restore()` needs to run.

## :star: Recommended workflow after changing dependencies
1. **Install or upgrade via Pixi whenever possible**
   - Example: `pixi add r-spelling` also brings in `r-hunspell`,
        letting renv treat them as external libraries.
2. **Run the generator/tests** so any renv-only packages (e.g. `khroma`)
    are available.
3. **Inspect renv status**
   ```bash
   pixi run Rscript -e "renv::status()"
   ```
4. **If packages show `installed = y`, `recorded = n`**, snapshot them:
   ```bash
   pixi run Rscript -e "renv::snapshot(prompt = FALSE)"
   ```
   - This updates `renv.lock` without touching the Pixi binaries.
5. **If you need to roll back to the lockfile state**, use:
   ```bash
   pixi run Rscript -e "renv::restore()"
   ```

## :memo: Practical notes
- Keep `.Rprofile` in version control
    so renv always auto-activates for CRAN-only packages.
- When the `khroma` conda-forge recipe lands,
    switch installation to Pixi and remove the renv copy;
    until then, expect `khroma` to be tracked in `renv.lock`.
- Treat renv warnings as bookkeeping:
    resolve them before committing so teammates don't inherit noisy runs.

## :book: References

- [Using R inside of Conda](https://blog.hpc.qmul.ac.uk/R-conda/):
    QMUL ITS Research Blog post that informed this approach for managing R packages within Conda-based environments.
