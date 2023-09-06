# RetailAnalistycsDB

Data base structure for retail analyzes project

## Content

The project implements a database structure with various functions, procedures and triggers.
There is also import and export to tsv files.
In addition to standard tables, presentation tables are created containing the necessary
information (their structure is indicated in the diagram).

## Structure

[diagram](https://dbdiagram.io/d/64f8113d02bd1c4a5e0c34af)

<img src="./images/diagram.png">

Description of procedures, functions and triggers - is in the comments in the code itself.

1. To move importing tsv files `make move`
2. To create a database `make create`
3. To drop a database `make drop`
4. To move tsv files and create a database `make`
