#!/bin/bash
# ralph-{{ENGINE}}.sh — Ralph loop on the {{ENGINE_LABEL}} engine.
#   ./ralph-{{ENGINE}}.sh 3        # up to three tasks
cd "$(dirname "$0")" || exit 1
ENGINE={{ENGINE}} exec ./ralph.sh "$@"
