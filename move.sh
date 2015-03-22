#!/bin/bash

# Usage:
#   git filter-branch -f --tree-filter '<absolute-path>/move.sh <dir-name>'

if [[ ! -e $1 ]] ; then
    mkdir -p $1
    git ls-tree --name-only $GIT_COMMIT | xargs -I files mv files $1
fi
