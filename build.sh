#! /usr/bin/env sh

[[ -z $COMMAND ]]   && COMMAND="build"
[[ -z $BUILD_DIR ]] && BUILD_DIR=src
[[ -z $OUT_FILE  ]] && OUT_FILE=bin/out

odin $COMMAND $BUILD_DIR -out:$OUT_FILE -thread-count:4 $@

