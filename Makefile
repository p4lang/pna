# SPDX-FileCopyrightText: 2020 The P4 Language Consortium
#
# SPDX-License-Identifier: Apache-2.0

SPEC=PNA
ROUGE_STYLE=github
ROUGE_CSS=style

all: ${SPEC}.pdf ${SPEC}.html

build:
${SPEC}.pdf: ${SPEC}.adoc pna.p4
	    time asciidoctor-pdf -v \
		-r asciidoctor-mathematical \
		-r asciidoctor-bibtex \
		-a pdf-fontsdir=resources/fonts \
		-a rouge-style=$(ROUGE_STYLE) $<

${SPEC}.html: ${SPEC}.adoc pna.p4
	time asciidoctor -v \
	-r asciidoctor-mathematical \
	-r asciidoctor-bibtex \
	-a rouge-css=$(ROUGE_CSS) $<

 
clean:
	/bin/rm -f ${SPEC}.pdf ${SPEC}.html

P4C=p4test
#P4C=p4test --Wdisable=uninitialized_out_param

check:
	echo "No pna example programs to compile yet"
