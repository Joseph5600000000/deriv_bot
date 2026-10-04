#!/usr/bin/env bash
set -e
cd "$(dirname "$0")/.."
CXX=${CXX:-g++}
$CXX -std=c++20 -Wall -O1 -g -fsanitize=address,undefined -o /tmp/tc_tests tests/test_engine.cpp engine/engine.cpp 2>&1 || \
$CXX -std=c++20 -Wall -O1 -o /tmp/tc_tests tests/test_engine.cpp engine/engine.cpp
/tmp/tc_tests
