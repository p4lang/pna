#! /bin/bash

# The scirpt will exit if the return code of a command is not 0.
set -e

# Before 2023-Mar-23, by default open source p4test would run a pass
# named "Predication" that would cause compile-time errors for _some_
# P4 programs with 'if' statements in action bodies, including several
# of the PNA example programs.

# With those versions of p4c, the following command line options
# disable that pass, enabling PNA example programs to compile using
# p4test without errors.

#P4TEST_OPTS="--excludeMidendPasses Predication"

# On 2023-Mar-23 this commit to p4c:
# https://github.com/p4lang/p4c/commit/ae32631178a3eaeca9fbd6f05b32f0728cc36ff2
# this pass was removed from p4test.  With those versions of p4test,
# it is an error to use the command line options above, because there
# is NO pass named Predication in p4test that can be disabled.

# With those versions of p4c, no extra command line options are
# needed:

P4TEST_OPTS=""


for j in *.p4
do
	echo "----------------------------------------"
	echo $j
	p4test $P4TEST_OPTS $j
done
