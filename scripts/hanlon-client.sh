#!/bin/bash
HANLON_SOURCE_PATH="$(git rev-parse --show-toplevel)"

docker run --rm -it -v $HANLON_SOURCE_PATH:/home/hanlon cscdock/hanlon-client $@
