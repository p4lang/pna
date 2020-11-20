# Portable NIC Architecture

The contents of this repository are a work in progress, intended to
lead towards a published Portable NIC Architecture specification
published by P4.org.


## Setup instructions

See the
[README](https://github.com/p4lang/p4-spec/blob/master/p4-16/spec/README.md)
for the P4_16 language specification for instructions on installing
software that enables you to produce HTML and PDF versions of the PNA
specification from its Madoko source file.


## Spec release process

Note: The following instructions were copied from the corresponding
README of the Portable Switch Architecture specification, and may need
some modifications when we reach the point of releasing a PNA
specification.

- increment version number in the document and commit
- merge to master and tag the commit with pna-version (e.g. pna-v0.9)
- generate the PDF and HTML
- checkout the gh-pages branch and copy to <root>/docs as PNA-<version>.[html,pdf]
- update links in <root>/index.html
- add files, commit and push the gh-pages branch
- checkout master, change the Title note to (working draft), commit and push

Someday we may write a script to do this.
