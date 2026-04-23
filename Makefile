# SPDX-FileCopyrightText: 2020 The P4 Language Consortium
#
# SPDX-License-Identifier: Apache-2.0

SPEC=PNA

all: build/${SPEC}.pdf

build/${SPEC}.pdf: ${SPEC}.mdk
	madoko --pdf -vv --png --odir=build $<

build/${SPEC}.pdf: p4.json
build/${SPEC}.pdf: pna.p4

clean:
	${RM} -rf build

P4C=p4test
#P4C=p4test --Wdisable=uninitialized_out_param

check:
	echo "No pna example programs to compile yet"
