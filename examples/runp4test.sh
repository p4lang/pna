#! /bin/bash

# The scirpt will exit if the return code of a command is not 0.
set -e

# With these extra command line options to p4test, it skips the Predication
# pass, which as of most p4c versions up to at least 2022-Oct-04, and
# probably for a while longer, causes p4test to give an error when an
# 'if' statement appears in a P4 action, and the compiler is not able to
# transform it into a ternary expression instead, i.e. expr ? val1 : val2.
# There are some PNA programs that we want to write, and check their syntax
# using p4test, that have such 'if' statements.

# This proposed PR for p4c would enable such programs to be compiled
# without error in a different way, but does not work yet as of 2022-Oct-04:
# https://github.com/p4lang/p4c/pull/3549

P4TEST_OPTS="--excludeMidendPasses Predication"

for j in *.p4
do
	echo "----------------------------------------"
	echo $j
	p4test $P4TEST_OPTS $j
done
