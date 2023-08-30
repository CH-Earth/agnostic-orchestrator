# Introduction
"Agnostic Orchestrator" is a simple `bash` script aiming to simplify
executing various processes involved in preparing meteorological and
geospatial data for setting up various hydrological models following the
concept of "model-agnostic framework". For a complete description of such
a framework, see [Knoben et al. 2022](https://doi.org/10.1029/2021WR031753).


The "Agnostic Orchestrator" is able to submit various dependant and
independant jobs to the [SLURM]() job scheduler that is widely used on
most High-performance Computing facilities (HPCs). Independant jobs are
submitted without following any hierarchy, while dependant jobs are
submitted following an order of execution that prepares necessary
meteorological and geospatial datasets for setting up hydrological models.
The order of executation follows the `dependency` capability of the SLURM
scheduler to submit jobs based on a hierarchy given.


The script uses a `JSON` configuration file to specify the:
 1. executables,
 2. relevant options and arguments of the provided executables,
 3. and hierarchy of job submissions to the scheduler.


# Usage
The script is highly optimized to be used on Digital Research Alliance of
Canada (DRA)'s Graham HPC. The executables that are commonly used with
this script is also highly optimized for the mentioned computing system.

To use the "Agnostic Orchestrator", please remember that you MUST have
access to Graham cluster with Digital Research Alliance of Canada (DRA)
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
    "met": "/path/to/extract-dataset.sh",
    "gis": "/path/to/extract-gis.sh",
    "remap": "easymore cli"
  },

  "args": {
    "met": [{
      "dataset": "RDRS",
      "dataset-dir": "/path/to/RDRS/",
      "variable": [
        "RDRS_v2.1_P_P0_SFC",
      ],
      "output-dir":"/path/to/outputs",
      "start-date":"1980-01-01T13:00:00",
      "end-date":"1980-12-31T12:00:00",
      "shape-file": "/path/to/catchments.shp",
     "_flags": [
        "submit-job",
        "parsable"
      ]
    }],
    "gis": [{
      "dataset": "landsat",
      "dataset-dir": "/path/to/Landsat/",
      "variable":"land-cover",
      "output-dir":"/path/to/landsat",
      "shape-file": "/path/to/catchments.shp",
      "print-geotiff": "true",
      "stat": [
        "frac",
        "coords"
      ],
      "_flags": [
	"include-na",
        "submit-job",
        "parsable"
      ]
    }],
    "remap": [{
      "case-name":"ab_models",
      "cache": "/path/to/temp_dir/",
      "shapefile": "/path/to/catchments.shp",
      "source-nc": "/path/to/*.nc*",
      "variable": [
        "RDRS_v2.1_P_P0_SFC",
      ],
      "output-dir": "/path/to/outputs/remapped/",
      "_flags": [
        "submit-job"
      ]
    }]
  },

  "order": {
    "met": 1,
    "gis": -1,
    "remap": 2
  }
}
```

As is shown in the `JSON` block above:
  1. First, the executables are listed and their paths are entered,
  2. Second, the arguments of the exetubales are detailed,
  3. And finally, the order of job submission to the SLURM scheduler is
     given, with `order` values of `-1` indicating independant jobs.

# A real-world example
An example to prepare meteorological and geospatial datasets to prepare
`MESH` hydrological/land-surface model is given in the [example](./example)
directory of the current repository.

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
