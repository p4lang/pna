# Portable NIC Architecture

The contents of this repository are a work in progress, intended to
lead towards a published Portable NIC Architecture specification
published by P4.org.


## Getting started

If you are new to the Portable NIC Architecture, we recommend starting
with the 18-minute video [Portable NIC Architecture
Update](https://www.youtube.com/watch?v=7SG-GxkQqfY) to get a quick
introduction to the basic ideas.

The latest version of the specification is given by:

+ its Madoko source file in [PNA.mdk](PNA.mdk), and
+ the include file [`pna.p4`](pna.p4)

HTML and PDF versions of the latest released version, and for the
latest working draft versions (udpated within an hour or so after each
commit to this repository), can be found on the P4.org specifications
page [here](https://p4.org/specs).


## Meetings to discuss changes to this specification

P4.org architecture work group meetings are held on most Mondays as
of 2022-2023.  See the calendar on the [P4.org Working Groups
page](https://p4.org/working-groups/) for dates, times, and
instructions for joining the meetings.

Notes from past meetings are maintained in a Google Docs document
[here](https://docs.google.com/document/d/1vX5GStrE01Pbj6d-liuuHF-4sYXjc601n5zJ4FHQXpM).
Notes from new meetings are added at the end of the document.

Issues are tracked using [Github issues on this
repository](https://github.com/p4lang/pna/issues) and suggested
changes are made by creating [Github pull
requests](https://github.com/p4lang/pna/pulls).

Some public files related to the P4.org architecture work group are
stored in this Google Drive folder: [P4 Architecture Working Group
Google Drive
folder](https://drive.google.com/drive/folders/13Wgcg0IUfMJTWOeIPzv95yqXkUHEGi4P)

In particular, the `meeting-recordings` sub-folder there contains
recordings of some recent meetings.  Here is a direct link to that
sub-folder: [meeting-recordings Google Drive
folder](https://drive.google.com/drive/folders/1I9gp7Wj4Fh-8ctpchldwXidRRwRbJLfp)


## Setup instructions for building specification from source

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
