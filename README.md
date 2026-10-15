# Introduction
"Agnostic Orchestrator" is a simple `bash` script aiming to simplify
executing various processes involved in preparing meteorological and
geospatial data for setting up various hydrological models following the
concept of "model-agnostic framework". For a complete description of such
a framework, see [Knoben et al. 2022](https://doi.org/10.1029/2021WR031753).


The "Agnostic Orchestrator" is able to submit various dependant and
independant jobs to the [SLURM](https://slurm.schedmd.com/) job scheduler
that is widely used on most High-performance Computing facilities (HPCs).
Independant processes are submitted without following any hierarchy, while
dependant processes are submitted following an order of execution that
prepares necessary meteorological and geospatial datasets for setting up
hydrological models. The order of executation follows the `dependency`
capability of the SLURM scheduler to submit jobs based on a hierarchy
given.


The script uses a `JSON` configuration file to specify the:
 1. executables,
 2. relevant options and arguments of the provided executables,
 3. hierarchy of job submissions to the scheduler,
 4. optional submission templates for running the processes as scheduler
    jobs.

Every process is run either through its own executable interface that
submits the job to the scheduler (e.g., `datatool`'s `extract-dataset.sh`
and `gistool`'s `extract-gis.sh`), or through a submission template that
is provided in the `submission` section of the configuration file
(e.g., `easymore.slurm`, `mesh.slurm`). A timestamped log file is created
next to the script, and the submission templates used in every run are
cached in `${HOME}/.orchestrator/orchestration_<date>`.


# Requirements
The "Agnostic Orchestrator" requires:
 1. `GNU bash` version 4.3 or later,
 2. `GNU sed`,
 3. `jq`,
 4. a `SLURM` cluster with the `sbatch` command.


# Usage
The script is developed and tested on Digital Research Alliance of
Canada (DRA)'s HPC clusters. The executables that are commonly used with
this script are also highly optimized for the mentioned computing system.

To use the "Agnostic Orchestrator", please remember that you MUST have
access to Digital Research Alliance of Canada (DRA)'s HPC clusters
[^2].

To access the script, simply access this online repository locally:
```console
foo@bar:~$ git clone https://github.com/kasra-keshavarz/agnostic-orchestrator.git # clone the repository
```

# `JSON` Configuration File
A sample of such a configuration file is in the following:
```json
{
  "exec": {
    "met": "/path/to/datatool/extract-dataset.sh",
    "gis": "/path/to/gistool/extract-gis.sh",
    "remap": "easymore cli"
  },

  "args": {
    "met": [{
      "dataset": "CaSR",
      "dataset-dir": "/path/to/CaSR/",
      "variable": [
        "CaSR_v3.1_P_P0_SFC",
      ],
      "output-dir":"/path/to/outputs",
      "start-date":"1980-01-01T00:00:00",
      "end-date":"1984-12-31T23:00:00",
      "shape-file": "/path/to/catchments.shp",
      "cluster": "/path/to/datatool/etc/clusters/ucalgary-arc.json",
      "cache": "$TMPDIR",
      "_flags": [
        "submit-job",
        "parsable"
      ]
    }],
    "gis": [{
      "dataset": "MODIS",
      "dataset-dir": "/path/to/MODIS/",
      "variable":"MCD12Q1.061",
      "output-dir":"/path/to/landcover/",
      "shape-file": "/path/to/catchments.shp",
      "fid": "COMID",
      "cluster": "/path/to/gistool/etc/clusters/ucalgary-arc.json",
      "cache": "$TMPDIR",
      "_flags": [
        "include-na",
        "submit-job",
        "parsable"
      ]
    }],
    "remap": [{
      "case-name":"averaged",
      "cache": "$TMPDIR/",
      "source-nc": "/path/to/*.nc*",
      "variable": [
        "CaSR_v3.1_P_P0_SFC",
      ],
      "output-dir": "/path/to/remapped/",
      "_flags": []
    }]
  },

  "order": {
    "met": 3,
    "gis": 2,
    "remap": 4
  },

  "submission": {
    "met": "",
    "gis": "",
    "remap": "/path/to/easymore.slurm"
  }
}
```

As is shown in the `JSON` block above:
  1. First, the executables are listed and their paths are entered,
  2. Second, the arguments of the exetubales are detailed; each process
     can hold an array of argument objects that are iterated over,
  3. Third, the order of job submission to the SLURM scheduler is given,
     with `order` values of `-1` indicating independant jobs,
  4. Fourth, an optional submission template is provided for each process;
     an empty string (`""`) means that the process is run through its own
     executable interface instead of a submission template.

Two special keys are supported inside every argument object:
  1. `_flags`: an array of flag names that is translated into `--flag`
     arguments (e.g., `--submit-job`, `--parsable`),
  2. `_arguments`: an array of positional arguments that is appended at the
     end of the argument list.

# Executation
The "Agnostic Orchestrator" can be run as following:
```console
foo@bar:~$ ./orchestrator.sh model-orchestration.json
```

# A real-world example
An example to prepare meteorological and geospatial datasets for the
`CATCHMENT` geospatial fabric of the model-agnostic framework publication,
and to run the model-specific workflows, is given in the
[example](./example) directory of the current repository.

# Support
Please open a new ticket on the Issues tab of the current repository in case of any problem.

# License
Agnostic Orchestrator Workflow<br>
Copyright (C) 2023, University of Calgary<br>

This program is free software: you can redistribute it and/or modify
it under the terms of the GNU General Public License as published by
the Free Software Foundation, either version 3 of the License, or
(at your option) any later version.

This program is distributed in the hope that it will be useful,
but WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
GNU General Public License for more details.

You should have received a copy of the GNU General Public License
along with this program.  If not, see <http://www.gnu.org/licenses/>.


[^1]: Knoben, Wouter Johannes Maria, Martyn P. Clark, Jerad Bales, Andrew Bennett, S. Gharari, Christopher B. Marsh, Bart Nijssen, Al Pietroniro, Ray Spiteri, Guoqiang Tang, and Andy Wood. "Community workflows to advance reproducibility in hydrologic modeling: Separating model‐agnostic and model‐specific configuration steps in applications of large‐domain hydrologic models." Water Resources Research 58, no. 11 (2022): e2021WR031753.
[^2]: For access, please contact Kasra Keshavarz at "kasra.keshavarz1 AT Ucalgary DOT ca"
