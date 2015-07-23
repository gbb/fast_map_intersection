#!/bin/bash 

# Fast parallel map intersection generator.
# Written by Graeme Bell, Norwegian Forest and Landscape Institute, Sep 2014.  
# Postgresql License (open source).
# This script writes lots of queries that form a large intersection, and runs them in parallel carefully 
# It's very useful for intersections on large geometry sets.
# IMPORTANT NOTE: It is __extremely__ important to have spatial indices on your source datasets!  
# Remember to put a spatial index on your final result if you need that.

######### Start of options #########

WORK_MEM=200   # set a slightly higher work_mem if you're in a hurry. 200-500 on vroom2 is ok. 100 on DB04. 
SPLIT=10       # e.g. 1 dataset = 10 pieces, 2 datasets=100 pieces, ...  (10-20 is a good number usually). 
JOBS=8	       # number of tasks to run in parallel. Vroom=4/8, db04=8, vroom2=16/32.

# Name of destination schema. Change this.
RESULT_SCHEMA='public'

# Name of table for the final results. Change this.
RESULT_TABLE='output_table1'

# SQL login command. Change this. 
# If you're using a username/password, you can use "PGPASSWORD=mypassword psql -h name -U username DBNAME"
DB_LOGIN='psql dbname'  
            
#           ######################    The Tricky Bit     ########################
# ---->     The 'make_sql' section is where you type your intersection SQL query.       <-----
#          Adjust the 'id' parts if you want, add extra columns, add extra WHERE clauses.
# Notes
# It may be helpful to put indices/primary key on your gid/id/sl_sdeid/objectid columns.
# You MUST leave the $1/$2/$3/$4/$5/$6 variables and the geo-index check in place.
# Edit the part between <<EOF / EOF
# parameter explanation: $1/$2=$i/$j (split variables)   $3=$SPLIT $4=$RESULT_SCHEMA.$RESULT_TABLE $5=${DB_LOGIN} $6=$WORK_MEM
# In this example we build all intersections of map1 and map2 and simply track the object ids they came from. 

function make_sql {

perl -pe 's/\n/ /g;' << EOF
echo "
SET work_mem TO '${6}MB';
CREATE UNLOGGED TABLE ${4}_${1}_${2} AS 
SELECT a.gid as map1gid, b.gid as map2gid, st_intersection(a.geom,b.geom) AS geom
FROM
  map1 a,
  map2 b
WHERE st_intersects(a.geom, b.geom) 
  AND a.gid%$3=${1} 
  AND b.gid%$3=${2};
" | ${5}
EOF

echo

}
 
######### End of options #########





# Specify how to generate all the indices on the final results. 
# You don't need to adjust this line normally but it's here just in case... 
# You may be using a 'geom' column instead of 'geo'?
MAKE_GEOIDX="create index ${RESULT_TABLE}_geoidx on ${RESULT_SCHEMA}.${RESULT_TABLE} using gist(geom);"

######## PROGRAM #########

# Delete any old working files and generate sql commands to do the work.

rm -f prep_commands tidy_commands split_commands join_commands index_commands

# Delete any result table/sequence with the same target name. Working/temporary tables are deleted in the next section. 

echo -e  "echo \"DROP SEQUENCE IF EXISTS ${RESULT_SCHEMA}.${RESULT_TABLE}_gid;\" | ${DB_LOGIN}" >> prep_commands
echo -e  "echo \"DROP TABLE IF EXISTS ${RESULT_SCHEMA}.${RESULT_TABLE};\" | ${DB_LOGIN}" >> prep_commands

# Create the split/join/tidy command sets. These are all generated together.

echo -en "echo \"CREATE SEQUENCE ${RESULT_TABLE}_gid; " >> join_commands
echo -en "CREATE TABLE ${RESULT_SCHEMA}.${RESULT_TABLE} AS SELECT nextval('${RESULT_TABLE}_gid') as gid,b.* FROM (SELECT * FROM " >> join_commands   

for i in `seq 0 $((SPLIT-1))`; do 
  for j in `seq 0 $((SPLIT-1))`; do

    make_sql "${i}" "${j}" "${SPLIT}" "${RESULT_SCHEMA}.${RESULT_TABLE}" "${DB_LOGIN}" "${WORK_MEM}" >> split_commands

    echo -e "echo \"DROP TABLE IF EXISTS ${RESULT_SCHEMA}.${RESULT_TABLE}_${i}_${j};\" | ${DB_LOGIN}" >> prep_commands
    echo -e "echo \"DROP TABLE IF EXISTS ${RESULT_SCHEMA}.${RESULT_TABLE}_${i}_${j};\" | ${DB_LOGIN}" >> tidy_commands

    echo -en "${RESULT_SCHEMA}.${RESULT_TABLE}_${i}_${j} UNION SELECT * FROM " >> join_commands 

  done
done

# Commands to close the union command, and analyze/index the new table.
echo -en "(select * from ${RESULT_SCHEMA}.${RESULT_TABLE}_0_0 limit 0) as tmp1 ) as b; alter table ${RESULT_SCHEMA}.${RESULT_TABLE} add PRIMARY KEY (gid);\" | ${DB_LOGIN}" >> join_commands
echo -e  "echo \"$MAKE_GEOIDX\" | ${DB_LOGIN}" >> index_commands
echo -e  "analyze ${RESULT_SCHEMA}.${RESULT_TABLE} | ${DB_LOGIN};" >> tidy_commands

## Do the work

# Prepare DB for new result
cat prep_commands | parallel -j $JOBS --progress

# Make partial results tables
cat split_commands | parallel -j $JOBS --progress

# Build final result table
cat join_commands | parallel -j $JOBS --progress

# Tidy up partial results in the database.
cat tidy_commands | parallel -j $JOBS --progress

# Generate index(es) on the result table
cat index_commands | parallel -j $JOBS --progress

# Clean up command files
rm prep_commands tidy_commands split_commands join_commands index_commands 



##### FINAL NOTES #####

# NOTE! Do not use a bounding box square to find intersection.
# This actually slows things down. The spatial index is already like a magic black box
#   which gets us all the intersecting polygons instantly.
# Using a bounding box actually prevents this technique working with non-geo tables.
