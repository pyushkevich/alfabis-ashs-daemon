#!/bin/bash

# Set PATH to the workspace tool
### PATH=/Users/pauly/tk/qtnsap/xc64dbg/Utilities/Workspace:$PATH

# Set the path to ASHS
### ASHS_ROOT=/Users/pauly/tk/ashs/ashs
### ASHS_ATLAS=/Users/pauly/tk/ashs/atlas/upenn_pmc_atlas/
ASHS_ROOT=/data/picsl/pauly/wolk/ashs-fast
ASHS_ATLAS=/data/picsl/pauly/wolk/atlas2016/ashs01/ashs_atlas_upennpmc_20170810

# This is the info on our service and provider
SERVICE_GITHASH=4dab78a1051cff7b8176e147ccce5940a5a5ffff
PROVIDER_NAME=picsl

# Create a temporary directory for this process
if [[ ! $TMPDIR ]]; then
  TMPDIR=$(mktemp -d /tmp/ashs_daemon.XXXXXX) || exit 1
fi

# Dereference a link - different calls on different systems
function dereflink ()
{
  if [[ $(uname) == "Darwin" ]]; then
    greadlink -f $1
  else
    readlink -f $1
  fi
}

# This function sends an error message to the server
function fail_ticket()
{
  local ticket_id=${1?}
  local message=${2?}

  itksnap-wt -dssp-tickets-fail $ticket_id "$message"
  sleep 2
}

# This is the main function that gets executed. Execution is very simple,
#   1. Claim a ticket under our service
#   2. If no ticket claimed, sleep return to 1
#   3. Extract necessary objects from the ticket
#   4. Run ASHS
function main_loop()
{
  # The code associated with the current service
  process_code=${1?}

  # The working directory
  workdir=${2?}

  while [[ true ]]; do

    # Try to claim for the ASHS service
    itksnap-wt -P -dssp-services-claim $SERVICE_GITHASH $PROVIDER_NAME $process_code 86400 | tee $TMPDIR/claim.txt

    # If negative result, sleep and continue
    if [[ ${PIPESTATUS[0]} -ne 0 ]]; then
      sleep 60
      continue
    fi

    # Get the ticket ID as the last line of output
    TICKET_ID=$(cat $TMPDIR/claim.txt | tail -n 1)

    # Set the work directory for this ticket
    WORKDIR=$workdir/$(printf ticket_%08d $TICKET_ID)

    # Download the files associated with this ticket
    itksnap-wt -P -dssp-tickets-download $TICKET_ID $WORKDIR > $TMPDIR/download.txt

    # If the download failed we mark the ticket as failed
    if [[ $? -ne 0 ]]; then
			fail_ticket $TICKET_ID "Failed to download the ticket after 1 attempts"
      continue
    fi

    # Get the workspace filename - this will be the last file downloaded
    WSFILE=$(cat $TMPDIR/download.txt | tail -n 1)

    # Identify the T1 and the T2 images
    T1_FILE=$(itksnap-wt -P -i $WSFILE -llf T1)
    if [[ $(echo $T1_FILE | wc -w) -ne 1 || ! -f $T1_FILE ]]; then
      fail_ticket $TICKET_ID "Missing tag 'T1' in ticket workspace"
      continue
    fi

    T2_FILE=$(itksnap-wt -P -i $WSFILE -llf T2)
    if [[ $(echo $T2_FILE | wc -w) -ne 1 || ! -f $T2_FILE ]]; then
      fail_ticket $TICKET_ID "Missing tag 'T2' in ticket workspace"
      continue
    fi

		# Provide callback info for ASHS to update progress and send log messages
		export ASHS_ROOT
    export ASHS_HOOK_SCRIPT=$(dirname $(dereflink $0))/ashs_alfabis_hook.sh
		export ASHS_HOOK_DATA=$TICKET_ID

    # The 8-digit ticket id string
    IDSTRING=$(printf %08d $TICKET_ID)

    # Ready to roll!
    $ASHS_ROOT/bin/ashs_main.sh \
      -a $ASHS_ATLAS \
      -g $T1_FILE -f $T2_FILE \
      -w $WORKDIR/ashs \
      -I $IDSTRING \
      -H -Q -z ashs_qsub_opts.sh

    # Check the error code
    if [[ $? -ne 0 ]]; then
      # TODO: we need to supply some debugging information, this is not enough
      # ASHS crashed - report the error
      fail_ticket $TICKET_ID "ASHS execution failed"
      continue
    fi

    # TODO: package up the results into a mergeable workspace (?)
    for what in heur corr_usegray corr_nogray; do
      $ASHS_ROOT/ext/$(uname)/bin/c3d \
        $WORKDIR/ashs/final/${IDSTRING}_left_lfseg_${what}.nii.gz \
        $WORKDIR/ashs/final/${IDSTRING}_right_lfseg_${what}.nii.gz \
        -shift 100 -replace 100 0 -add \
        -o $WORKDIR/${IDSTRING}_lfseg_${what}.nii.gz
    done

    # Create a new workspace
    itksnap-wt -i $WSFILE \
      -las $WORKDIR/${IDSTRING}_lfseg_corr_usegray.nii.gz -psn "JLF/CL result" \
      -las $WORKDIR/${IDSTRING}_lfseg_corr_nogray.nii.gz -psn "JLF/CL-lite result" \
      -las $WORKDIR/${IDSTRING}_lfseg_heur.nii.gz -psn "JLF result" \
      -labels-clear \
      -labels-add $ASHS_ATLAS/snap/snaplabels.txt 0 "Left %s" \
      -labels-add $ASHS_ATLAS/snap/snaplabels.txt 100 "Right %s" \
      -o $WORKDIR/${IDSTRING}_results.itksnap \
      -dssp-tickets-upload $TICKET_ID

    # Set the result to success
    itksnap-wt -dssp-tickets-success $TICKET_ID

  done
}

# -------------------------
# Main Entrypoint of Script
# -------------------------
if [[ $# -ne 2 ]]; then
  echo "Usage: ashs_daemon.sh service_desc workdir"
  exit
fi

main_loop "$@"
