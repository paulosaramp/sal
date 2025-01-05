#!/bin/bash
db2 connect to SAMPLE
db2 -tvf CREATE_TABLES.sql
db2 -tvf VIEWS.sql
db2 -td@ -vf PROGRAMMABLE.sql
db2 -tvf INSERT_BASE_DATA.sql


