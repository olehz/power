#!/bin/bash
set -o errexit
set -o pipefail
set -o nounset

HASHMEM=8000
REGION='UA'
MAXMERGE=5
DIR='/home/oz/SDD/import'
USER='postgres'
DB='osm'

rm $DIR/data/planet-latest.osm.pbf
wget http://download.geofabrik.de/europe/ukraine-latest.osm.pbf -O $DIR/data/planet-latest.osm.pbf

imposm3 import -diff=false -config=config/imposm.json -read $DIR/data/planet-latest.osm.pbf -write -overwritecache=true;

psql -U$USER -d$DB -v scm=import < sql/power.sql
#psql -U$USER -d$DB -v scm=import < sql/topo.sql


TABLES=('powerlines' 'powerplants' 'substations')
for TABLE in ${TABLES[@]};do
	psql -U$USER -d$DB -c "
		DROP TABLE IF EXISTS public.$TABLE CASCADE;
		ALTER TABLE import.$TABLE SET SCHEMA public;"
done