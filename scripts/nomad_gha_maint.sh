#! /usr/bin/bash
#
# nomad_gha_maint.sh  -- periodic script to do nomad gc and gha orphan job gc
#
# Installation notes:
#
# Copy this script to ~/bin/nomad_gha_maint.sh
#
# Enable mouse mode for scrolling back in tmux:
# echo 'set -g mouse' >> ~/.tmux.conf
# tmux source-file ~/.tmux-config
#
# Create new tmux session:
# tmux new-session -s nomad-gc
#
# Run script
# ~/bin/nomad_gha_naint.sh
#
# Disconnect from session:
# Ctrl-b d
#
# Attach to tmux session periodically to check results:
# tmux a -t nomad-gc
#
set -uo pipefail

function gha_orphan_gc()
{
  local ns="$1"
  local now_secs="$2"
  echo -e "\nChecking for orphan gha jobs in $ns:"
  sudo -E nomad status --namespace "$ns"
  for job in $(sudo -E nomad status -namespace "$ns" | grep -e 'gha-[0-9]' | mawk '{print $1}') ; do
    status=$(sudo -E nomad alloc logs -namespace "$ns" -stdout \
        $(sudo -E nomad status -verbose -namespace "$ns" "$job" | tail -1 | mawk '{print $1}') | tail -1)
    echo -e "\n[$ns] $job\n$status"
    job_date=$(echo $status | mawk '{printf "%s %s",$1,$2}')
    job_date_secs=$(date -u -d "${job_date:0:-1}" +%s)
    if grep -q "Listening for Jobs" <<< "$status" && [ $(( now_secs - job_date_secs )) -gt "3600" ] ; then
      echo "Purging $job:"
      sudo -E nomad stop -namespace "$ns" -purge "$job"
    fi
  done
}

while true; do
  fmt="%Y-%m-%d %H:%M:%SZ"
  now=$(date -u +"$fmt")
  now_secs=$(date -u -d "$now" +%s)
  echo -e "\n------[ $now ]------"
  gha_orphan_gc default "$now_secs"
  gha_orphan_gc etl "$now_secs"
  gha_orphan_gc sandbox "$now_secs"
  gha_orphan_gc prod "$now_secs"
  echo -e "\nRun Nomad Garbage Collection\n"
  sudo -E nomad system gc
  echo "Sleeping 5 minutes..."
  sleep 300
done
