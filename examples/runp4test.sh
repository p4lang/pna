#! /bin/bash

for j in *.p4
do
	echo "----------------------------------------"
	echo $j
	p4test $j
done
