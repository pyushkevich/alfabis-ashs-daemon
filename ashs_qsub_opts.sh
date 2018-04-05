#!/bin/bash
WORKDIR=${1?}
STAGE=${2?}

case $STAGE in
  2) 
    echo "-pe serial 2"
    ;;
  5)
    echo "-l h_vmem=12.1G,s_vmem=12G"
    ;;
esac


