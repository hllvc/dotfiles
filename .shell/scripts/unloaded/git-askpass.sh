#!/bin/sh
case "$1" in
  Username*) echo "x-access-token" ;;
  Password*) op read "op://Stackguardian/StackGuardian Token/token" ;;
esac
