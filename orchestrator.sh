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

# logging date string
dateLog="$(date +'%Y%m%d_%H%M%S')"

# global variables
log="$(dirname $0)/orchestrator_${dateLog}.log"
log="$(realpath $(dirname $0)/orchestrator_${dateLog}.log)"

# Main message
echo "$(basename $0): Model-agnostic workflow job submission to SLURM scheduler"

# create log file
if [[ -e $log ]]; then
  rm $log
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
jqScript="$(dirname $0)/assets/json-funcs.jq"

extract () {
  local func=$1
  jq -r "$(cat $jqScript) $func" $conf;
}

# The `model-agnostic.json` file consists of four main sections
#   1. exec: where the executable paths are defined,
#   2. args: where the arguments to the executables are iterated.
#   3. order: where the order of each section for execution is given
#   4. submission: where the submission script for the elements are provided

# Register the main keys of $conf: `exec`, `args`, and `order`
mainKeys=("exec" "args" "order" "submission")
# Reading the sub-keys from any element of $mainKeys 
mapfile -t subKeys < <(jq -r ".${mainKeys[0]} | keys[]" ${conf})


################################
# Checking requirements of $conf
################################
# Check the `length` of each key and if unequal, throw an error
initCount=$(extract "count(.${mainKeys[0]})")
for key in "${mainKeys[@]}"; do
  c=$(extract "count(.${key})")
  if [[ $c -ne $initCount ]]; then
    echo "$(basename $0): ERROR! The arguments provided in main arrays"
      "are not equal"
      exit 1;
  fi
done

# Check if the $mainKeys are provided in $conf
mapfile -t derivedKeys< <(jq -r "keys[]" ${conf})

for key in "${derivedKeys[@]}"; do
  for mainKey in "${mainKeys[@]}"; do
    if [[ "${key,,}" == "${mainKey,,}" ]]; then
      break 2
    fi
  done

  # if break does not happen, throw an error
  echo "$(basename $0): ERROR! \`$key\` is not found in $conf"
  echo "key is ${key} and mainKey is ${mainKey}"
  exit 1;

done


#####################
# Running executables 
#####################
# first execute those with `order` value of `-1` (i.e., independent
# processes)
# Tip: `indeps` is an array containing "independent" processes
mapfile -t indeps < <(extract "select_independants(.order)")

for sec in "${indeps[@]}"; do

  # select the executable and related arguments
  executable=$(extract ".exec.${sec}")

  # check how many sets of `args` are provided for each `section`
  iters=$(extract "count(.args.${sec})")

  # iterate over the `args` provided in each `section`
  for i in $(seq 1 $iters); do
    # index
    idx=$(( i - 1 )) # since JSON/jq array indices start from 0

    # argument value
    arg=$(extract "parse_args(.args.${sec}[$idx])")

    # submission script provided?
    submission_script=$(jq -r ".submission.${sec}" $conf)

    # executing
    if [[ "$submission_script" != "" ]]; then
      sbatch ${submission_script} --wrap "${executable} ${arg} >> ${log} 2>&1)"
    else
      $executable $arg 2>> $log;
    fi

    # relevant message
    echo "$(basename $0): Script for independant :${sec}:#${i} process" \
      "is executed"

  done
done


# second execute those with `order` value of greater than 1 (i.e.,
# dependant) and ordered monotonically
# Tip: `deps` is in array containing "dependant" processes 
mapfile -t deps < <(extract "select_dependants(.order)")

# number of iterations needed, with each iterations being the parent
# process of the next one
dep_iters="${#deps[@]}"

# make an empty ID array to keep track of submitted SLURM jobs
ID=()

for iter in $(seq 1 $dep_iters); do
  # index in Bash arrays start from 0 
  idx=$(( $iter - 1 ))

  # make the $sec variable based on $idx and $deps
  sec="${deps[$idx]}"

  # select executable and run the process
  executable=$(extract ".exec.${sec}")
 
  # check number of iterations required for each `$deps` process
  sub_iters=$(extract "count(.args.${sec})")

  for sub_iter in $(seq 1 $sub_iters); do
    # jq array index starts from 0
    sub_idx="$(( $sub_iter - 1 ))"

    # argument
    arg=$(extract "[parse_args(.args.${sec}[$sub_idx])] | join(\"\")" | tr -d '\n')

    # submission script provided?
    submission_script=$(jq -r ".submission.${sec}" $conf)

    # executation part 
    # if parent process
    if [[ $idx -eq 0 ]]; then
      # argument value
      # save SLURM submission ID(s)
      if [[ "$submission_script" != "" ]]; then
        # Prepare the line that needs to be added to the SLURM submission
        # script
        parse_line="#SBATCH --parsable"
        eval_line="srun ${executable} ${arg} 2>> ${log}"

        # Make a temporary file in the cache
        submission_script_name="$(basename ${submission_script})"
        cp "${submission_script}" "${cache}/${submission_script_name}"

        # add the prepared line to the end of the file
        sed -i "2i\\${parse_line}" "${cache}/${submission_script_name}"
        echo "${eval_line}" >> "${cache}/${submission_script_name}"

        # execute the script
        ID+=("$(sbatch ${cache}/${submission_script_name})")

      else
        ID+=("$(${executable} --parsable ${arg})")

      fi

      # print parent message
      echo "$(basename $0): Script for :${sec}:#${sub_iter} process" \
        "is executed as a parent process with ID ${ID[-1]}"

    # if a child process
    else
 
      # make comma delimited values of SLURM batch IDs
      printf -v joined '%s,' "${ID[@]}"
      csvID="$(echo "${joined%,}")"

      # submit child jobs dependant on the parent
      if [[ "$submission_script" != "" ]]; then
        # Prepare the line that needs to be added to the SLURM submission
        # script
        dependency_line="#SBATCH --dependency=afterok:${csvID}"
        parsable_line="#SBATCH --parsable"
        eval_line="srun ${executable} ${arg} 2>> ${log}"

        # Make a temporary file in the cache
        submission_script_name="$(basename ${submission_script})"
        cp "${submission_script}" "${cache}/${submission_script_name}"

        # add the prepared line to the end of the file
        sed -i "2i\\${dependency_line}" "${cache}/${submission_script_name}"
        sed -i "3i\\${parsable_line}" "${cache}/${submission_script_name}"
        echo "$eval_line" >> "${cache}/${submission_script_name}"

        # execute the script
        ID+=("$(sbatch ${cache}/${submission_script_name})")

      else
        # execute the script as is, the script must accept --dependency
        ID+=("$(${executable} ${arg} --parsable --dependency="${csvID}" 2>> $log)")
      fi

      # print child message
      echo "$(basename $0): Script for :${sec}: for the #${sub_iter}" \
        "process is executed as a child process for parent process ID(s) of" \
        "${csvID}"
    fi

  done
done
