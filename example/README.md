# A real-world application
The [model-orchestration.json](./model-orchestration.json) configuration
file is the experiment specification used in the model-agnostic framework
publication to prepare meteorological and geospatial datasets for, and to
run, a set of land-surface/hydrological models on the `CATCHMENT`
geospatial fabric. It configures the following workflows, in order of
execution:

 1. `geofabric`: construction of the geospatial fabric,
 2. `gis`: extraction of geospatial attributes (land-cover, elevation,
    soil classes),
 3. `met`: extraction of meteorological forcing data,
 4. `remap`: remapping of the meteorological data onto the geospatial
    fabric using `easymore`,
 5. model-specific workflows: `mesh`, `summa`, `fuse`, `marrmot`, and
    `hype`,
 6. `tar` and `rm`: archiving of the outputs and removal of the
    intermediate files.

This example also demonstrates most of the configuration capabilities of
the orchestrator: multiple argument objects for a single process (`gis`),
flag and positional arguments (`_flags`, `_arguments`), processes that are
submitted through their own executable interface (empty `submission`
values), and processes that are submitted through SLURM submission
templates (e.g., `geofabric.slurm`, `easymore.slurm`).

Paths of the form `/path/to/...` are placeholders and must be adapted to
the target system. Input data paths of the form `/work/comphyd_lab/...`
are those of the publication's data on Digital Research Alliance of
Canada (DRA)'s HPC clusters. For access, contact Kasra Keshavarz at
"kasra.keshavarz1 AT ucalgary DOT ca".
