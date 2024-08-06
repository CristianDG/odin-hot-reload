#! /usr/bin/env sh

[[ -z $1 ]] && echo "usage: build_lib <lib_name>" && exit 1

lib_name=$1

odin build "src/$lib_name" -out:"bin/$lib_name" -build-mode:shared -no-entry-point -thread-count:4 "${@:2}"

