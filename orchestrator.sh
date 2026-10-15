#!/bin/bash    

# Copyright (C) 2023-2025 University of Calgary
#
# This program is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 3 of the License, or
# (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program.  If not, see <http://www.gnu.org/licenses/>.

# input variables
conf="$1"

# logging date string (the PID makes concurrent runs unique)
dateLog="$(date +'%Y%m%d_%H%M%S')_$$"

# global variables
log="$(dirname "$0")/orchestrator_${dateLog}.log"
log="$(realpath "$(dirname "$0")/orchestrator_${dateLog}.log")"

# Main message
echo "$(basename $0): Model-agnostic workflow job submission to SLURM scheduler"

# create log file
if [[ -e $log ]]; then
  rm "$log"
fi

# create log file
touch "$log"

# cache file
cache="${HOME}/.orchestrator/orchestration_${dateLog}"
mkdir -p "${cache}"

# the header is the date the script is run
date >> $log
echo "$(basename $0): details are logged in ${log}"
echo "$(basename $0): cache files are in ${cache}"
echo "$(basename $0): job logs are in ${cache}"


#####################################
# Necessary functions and definitions
#####################################
jqScript="$(dirname "$0")/assets/json-funcs.jq"

extract () {
  local func=$1
  jq -r "$(cat "$jqScript") $func" "$conf";
}

# join a list of values into a colon-separated string (SLURM expects
# `afterok:id1:id2:...` when a job depends on several jobs); the result
# is stored in the variable whose name is passed as the first argument,
# without changing the global IFS
join_ids () {
  local variable=$1
  shift
  local IFS=':'
  local joined="$*"
  printf -v "$variable" '%s' "$joined"
}

# submit a single invocation and store the returned SLURM job ID in the
# global `submitted_job_id` variable; returns non-zero when the
# submission command itself fails
submit_job () {
  local submission_script=$1
  local executable=$2
  local arg=$3
  local dependency_ids=$4
  local cache_label=$5
  local submission_script_name parsable_line dependency_line

  if [[ "$submission_script" != "" ]]; then
    # Prepare the line that needs to be added to the SLURM submission
    # script
    parsable_line="#SBATCH --parsable"

    # Make a temporary file in the cache; the label keeps every cached
    # template unique per submission, so templates that share a basename
    # do not overwrite each other
    cache_label="${cache_label//\//_}"
    submission_script_name="${cache_label}.$(basename "$submission_script")"
    cp "$submission_script" "${cache}/${submission_script_name}"

    # add the prepared line(s) to the file; the dependency line is only
    # added for invocations that have parent jobs
    if [[ -n "$dependency_ids" ]]; then
      dependency_line="#SBATCH --dependency=afterok:${dependency_ids}"
      sed -i "2i\\${dependency_line}" "${cache}/${submission_script_name}"
      sed -i "3i\\${parsable_line}" "${cache}/${submission_script_name}"
    else
      sed -i "2i\\${parsable_line}" "${cache}/${submission_script_name}"
    fi
    echo "srun ${executable} ${arg} 2>> ${log}" >> "${cache}/${submission_script_name}"

    # execute the script
    submitted_job_id="$(sbatch "${cache}/${submission_script_name}")"

  else
    # execute the script as is, the script must accept --parsable and
    # --dependency
    if [[ -n "$dependency_ids" ]]; then
      submitted_job_id="$(${executable} --parsable ${arg} --dependency="${dependency_ids}" 2>> "$log")"
    else
      submitted_job_id="$(${executable} --parsable ${arg} 2>> "$log")"
    fi

  fi

  return $?
}

# a parsable SLURM job ID is either `jobid` or `jobid;cluster`
valid_job_id () {
  local job_id=$1
  local job_id_pattern='^[0-9]+(;[[:alnum:]_.-]+)?$'
  [[ $job_id =~ $job_id_pattern ]]
}

# append a machine-readable submission record to the log file
log_submission () {
  local level=$1
  local section=$2
  local invocation=$3
  local total=$4
  local dependency_ids=$5
  local job_id=$6
  local record="event=submit timestamp=$(date +'%Y-%m-%dT%H:%M:%S%z') level=${level} process=${section} invocation=${invocation}/${total} dependency_ids=${dependency_ids:--} job_id=${job_id}"
  printf '%s\n' "$record" >> "$log"
}

# The `model-agnostic.json` file consists of four main sections
#   1. exec: where the executable paths are defined,
#   2. args: where the arguments to the executables are iterated.
#   3. order: where the order of each section for execution is given
#   4. submission: where the submission script for the elements are provided

# Register the main keys of $conf: `exec`, `args`, `order`, `submission`
mainKeys=("exec" "args" "order" "submission")


################################
# Checking requirements of $conf
################################
# Check that all main sections are provided in $conf
for key in "${mainKeys[@]}"; do
  if [[ "$(jq -r "has(\"${key}\")" "$conf")" != "true" ]]; then
    echo "$(basename $0): ERROR! the \`${key}\` section is missing in ${conf}" >&2
    exit 1
  fi
done

# Check that no unknown top-level keys are provided in $conf
mapfile -t derivedKeys < <(jq -r "keys[]" "$conf")
for key in "${derivedKeys[@]}"; do
  found=false
  for mainKey in "${mainKeys[@]}"; do
    if [[ "${key}" == "${mainKey}" ]]; then
      found=true
      break
    fi
  done
  if [[ "${found}" == "false" ]]; then
    echo "$(basename $0): ERROR! \`${key}\` is not a valid top-level key in ${conf}" >&2
    echo "$(basename $0): valid top-level keys are: ${mainKeys[*]}" >&2
    exit 1
  fi
done

# Check that every section defines the same component keys
execKeys="$(extract '.exec | keys | join(",")')"
for key in "${mainKeys[@]}"; do
  sectionKeys="$(extract ".${key} | keys | join(\",\")")"
  if [[ "$sectionKeys" != "$execKeys" ]]; then
    echo "$(basename $0): ERROR! the component keys of \`.${key}\` do not" \
      "match the ones of \`.exec\` in ${conf}" >&2
    echo "$(basename $0): \`.exec\` keys: ${execKeys}" >&2
    echo "$(basename $0): \`.${key}\` keys: ${sectionKeys}" >&2
    exit 1
  fi
done

# Check the value types of every section
badValues="$(extract '[.exec | to_entries[] | select((.value | type) != "string" or .value == "") | .key] | join(",")')"
if [[ -n "$badValues" ]]; then
  echo "$(basename $0): ERROR! \`.exec\` values must be non-empty strings," \
    "one for every process; offending key(s): ${badValues}" >&2
  exit 1
fi

badValues="$(extract '[.submission | to_entries[] | select((.value | type) != "string") | .key] | join(",")')"
if [[ -n "$badValues" ]]; then
  echo "$(basename $0): ERROR! \`.submission\` values must be strings" \
    "(use \"\" when a process runs through its own interface);" \
    "offending key(s): ${badValues}" >&2
  exit 1
fi

badValues="$(extract '[.args | to_entries[] | select((.value | type) != "array") | .key] | join(",")')"
if [[ -n "$badValues" ]]; then
  echo "$(basename $0): ERROR! \`.args\` values must be arrays of" \
    "argument objects; offending key(s): ${badValues}" >&2
  exit 1
fi

badValues="$(extract '[.args | to_entries[] | select(([.value[] | type == "object"] | all) | not) | .key] | join(",")')"
if [[ -n "$badValues" ]]; then
  echo "$(basename $0): ERROR! every entry of an \`.args\` array must be an" \
    "argument object; offending key(s): ${badValues}" >&2
  exit 1
fi

# Check that `order` values are either -1 (independent) or positive
# integers; `0`, other negative values, and non-integers are invalid
badValues="$(extract '[.order | to_entries[] | (.value | tostring) as $value | select(($value | test("^-1$|^[1-9][0-9]*$")) | not) | .key] | join(",")')"
if [[ -n "$badValues" ]]; then
  echo "$(basename $0): ERROR! \`.order\` values must be -1 for independent" \
    "processes or positive integers for ordered processes;" \
    "offending key(s): ${badValues}" >&2
  exit 1
fi

# Check that submission templates and path-like executables exist
# before any job is submitted
mapfile -t allProcesses < <(extract '.exec | keys | .[]')
for sec in "${allProcesses[@]}"; do

  submission_script=$(jq -r ".submission[\"${sec}\"]" "$conf")
  if [[ "$submission_script" != "" ]]; then
    if [[ ! -f "$submission_script" || ! -r "$submission_script" ]]; then
      echo "$(basename $0): ERROR! the submission template of \`${sec}\` is" \
        "not a readable file: ${submission_script}" >&2
      exit 1
    fi
  fi

  executable=$(extract ".exec[\"${sec}\"]")
  executable_bin="${executable%% *}"
  if [[ "$executable_bin" == */* && ! -x "$executable_bin" ]]; then
    echo "$(basename $0): ERROR! the executable of \`${sec}\` is not an" \
      "executable file: ${executable_bin}" >&2
    exit 1
  fi

done


#####################
# Running executables 
#####################
# first execute those with `order` value of `-1` (i.e., independent
# processes); they are submitted through the same template or interface
# as the first level, but without any dependency, and their submission
# IDs are only recorded in the log, never used as dependencies
# Tip: `indeps` is an array containing "independent" processes
mapfile -t indeps < <(extract "select_independants(.order)")

for sec in "${indeps[@]}"; do

  # select the executable and related arguments
  executable=$(extract ".exec[\"${sec}\"]")

  # check how many sets of `args` are provided for each `section`
  iters=$(extract "count(.args[\"${sec}\"])")

  # submission script provided?
  submission_script=$(jq -r ".submission[\"${sec}\"]" "$conf")

  # iterate over the `args` provided in each `section`
  for i in $(seq 1 $iters); do
    # index
    idx=$(( i - 1 )) # since JSON/jq array indices start from 0

    # argument value
    arg=$(extract "[parse_args(.args[\"${sec}\"][$idx])] | join(\"\")" | tr -d '\n')

    # submit the independent invocation without any dependency
    if ! submit_job "$submission_script" "$executable" "$arg" "" "${sec}_${i}"; then
      echo "$(basename $0): ERROR! submission of independant :${sec}:#${i}" \
        "failed" >&2
      exit 1
    fi
    job_id="$submitted_job_id"

    # a submission must return a parsable SLURM job ID
    if ! valid_job_id "$job_id"; then
      echo "$(basename $0): ERROR! submission of independant :${sec}:#${i}" \
        "did not return a valid job ID: \`${job_id}\`" >&2
      exit 1
    fi

    # machine-readable submission record in the log file
    log_submission "-1" "$sec" "$i" "$iters" "" "$job_id"

    # relevant message
    echo "$(basename $0): Script for independant :${sec}:#${i} process is" \
      "executed with SLURM job ID ${job_id}"

  done
done


# second execute those with a positive `order` value (i.e., dependant
# processes); distinct `order` values define execution levels, and every
# invocation of a level is only eligible to run after all invocations of
# the immediately preceding level have completed successfully
mapfile -t ordered_levels < <(extract "select_levels(.order)")

# submission IDs of the preceding level; empty for the first level
parent_ids=()

for level in "${ordered_levels[@]}"; do

  # submission IDs collected while submitting the current level
  level_ids=()

  # processes whose `order` value equals the current level
  mapfile -t level_processes < <(extract "select_processes(.order; ${level})")

  # all invocations of this level share the same dependency: the
  # complete set of submission IDs from the preceding level only
  dependency_ids=""
  if [[ ${#parent_ids[@]} -gt 0 ]]; then
    join_ids dependency_ids "${parent_ids[@]}"
  fi

  for sec in "${level_processes[@]}"; do

    # select executable and run the process
    executable=$(extract ".exec[\"${sec}\"]")

    # check number of iterations required for each process
    sub_iters=$(extract "count(.args[\"${sec}\"])")

    # submission script provided?
    submission_script=$(jq -r ".submission[\"${sec}\"]" "$conf")

    for sub_iter in $(seq 1 $sub_iters); do
      # jq array index starts from 0
      sub_idx="$(( $sub_iter - 1 ))"

      # argument
      arg=$(extract "[parse_args(.args[\"${sec}\"][$sub_idx])] | join(\"\")" | tr -d '\n')

      # submit the invocation; a failed submission stops the workflow
      # before any dependent job is submitted
      if ! submit_job "$submission_script" "$executable" "$arg" "$dependency_ids" "${sec}_${sub_iter}"; then
        echo "$(basename $0): ERROR! submission of :${sec}:#${sub_iter} at" \
          "level ${level} failed; no dependent job is submitted" >&2
        exit 1
      fi
      job_id="$submitted_job_id"

      # a submission must return a parsable SLURM job ID
      if ! valid_job_id "$job_id"; then
        echo "$(basename $0): ERROR! submission of :${sec}:#${sub_iter} at" \
          "level ${level} did not return a valid job ID: \`${job_id}\`" >&2
        exit 1
      fi

      # keep the job ID as a dependency of the next level
      level_ids+=("$job_id")

      # machine-readable submission record in the log file
      log_submission "$level" "$sec" "$sub_iter" "$sub_iters" "$dependency_ids" "$job_id"

      # print submission message
      echo "$(basename $0): Script for :${sec}:#${sub_iter} process is" \
        "executed at level ${level} with parent ID(s) of ${dependency_ids:--}" \
        "and SLURM job ID ${job_id}"

    done

  done

  # the jobs of the current level become the parents of the next level;
  # independent (`order = -1`) job IDs are never added here
  parent_ids=("${level_ids[@]}")

done
