#!/bin/bash
set -x -e

# Set PATH to the workspace tool
PATH=/data/picsl/pauly/bin:$PATH

# Extract the hook data from the environment
ticket_id=${ASHS_HOOK_DATA?}

# Simple case statement to split 
case "${1?}" in 
  progress)
    itksnap-wt -dssp-tickets-set-progress $ticket_id ${2?} ${3?} ${4?}
    ;;
  info|warning|error)
    itksnap-wt -dssp-tickets-log $ticket_id ${1?} "${2?}"
    ;;
  attach)
    itksnap-wt -dssp-tickets-attach $ticket_id "${2?}" "${3?}"
    ;;
esac
