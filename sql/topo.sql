DROP SCHEMA IF EXISTS topopology CASCADE;
DROP SCHEMA IF EXISTS powerlines_topo CASCADE;
DROP TABLE IF EXISTS import.powerlines_vertices_pgr;
DROP EXTENSION postgis_topology;

CREATE EXTENSION postgis_topology;
SELECT topology.CreateTopology('powerlines_topo', 4326, 0);
SELECT topology.AddTopoGeometryColumn('powerlines_topo', 'import', 'powerlines', 'topo_geom', 'LINESTRING');
UPDATE import.powerlines SET topo_geom = topology.toTopoGeom(geometry, 'powerlines_topo', 1, 0);


DROP TABLE IF EXISTS import.lines;CREATE TABLE import.lines AS
SELECT 
    ROW_NUMBER() OVER() id,
    (v[1] >= 35 AND v[1] < 110) OR (v[2] >= 35 AND v[2] < 110) AS v35,
    (v[1] >= 110 AND v[1] < 150) OR (v[2] >= 110 AND v[2] < 150) AS v110,
    (v[1] >= 150 AND v[1] < 220) OR (v[2] >= 150 AND v[2] < 220) AS v150,
    (v[1] >= 220 AND v[1] < 330) OR (v[2] >= 220 AND v[2] < 330) AS v220,
    (v[1] >= 330 AND v[1] < 400) OR (v[2] >= 330 AND v[2] < 400) AS v330,
    (v[1] >= 400 AND v[1] < 500) OR (v[2] >= 400 AND v[2] < 500) AS v400,
    (v[1] >= 500 AND v[1] < 750) OR (v[2] >= 500 AND v[2] < 750) AS v500,
    (v[1] >= 750) OR (v[2] >= 750) AS v750,
    e.geom AS geometry
FROM powerlines_topo.edge e,
     powerlines_topo.relation rel,
     import.powerlines l
INNER JOIN LATERAL (SELECT ARRAY[
    CASE WHEN TRIM(v[1]) ~* '^[0-9;]+$' THEN v[1]::integer/1000 ELSE 0 END,
    CASE WHEN TRIM(v[2]) ~* '^[0-9;]+$' THEN v[2]::integer/1000 ELSE 0 END
    ] AS v FROM string_to_array(TRIM(voltage), ';') AS v
) AS v ON TRUE
WHERE e.edge_id = rel.element_id AND rel.topogeo_id = (l.topo_geom).id;

DROP TABLE IF EXISTS import.powerlines;ALTER TABLE import.lines RENAME TO powerlines;

ALTER TABLE import.powerlines ADD COLUMN source bigint, ADD COLUMN target bigint;
ALTER TABLE import.powerlines ADD COLUMN cost float, ADD COLUMN reverse_cost float;
UPDATE import.powerlines SET cost = ST_Length(geometry::geography), reverse_cost = ST_Length(geometry::geography);
SELECT createTopology('import.powerlines', 0, 'geometry');


CREATE TEMPORARY TABLE dup AS
SELECT ids[1] AS id, ids[2:] AS ids FROM (
SELECT ARRAY_AGG(id ORDER BY id) ids FROM import.powerlines_vertices_pgr
GROUP BY the_geom
HAVING COUNT(*) > 1
) z;

UPDATE import.powerlines SET target = d.id FROM dup d WHERE target = ANY(d.ids);
UPDATE import.powerlines SET source = d.id FROM dup d WHERE source = ANY(d.ids);

DROP TABLE import.powerlines_vertices_pgr;

UPDATE import.powerlines l SET source = s.id FROM import.substations s WHERE s.centre = ST_StartPoint(l.geometry);
UPDATE import.powerlines l SET target = s.id FROM import.substations s WHERE s.centre = ST_EndPoint(l.geometry);


--CREATE TEMPORARY TABLE links AS
--SELECT v.id AS id2, s.id AS id1 FROM import.powerlines_vertices_pgr v
--INNER JOIN import.substations s ON s.centre = v.the_geom;
--
--UPDATE import.powerlines l SET source = id1 FROM links WHERE source = id2;
--UPDATE import.powerlines l SET target = id1 FROM links WHERE target = id2;


--CREATE TEMPORARY TABLE links AS
--SELECT s.id AS id1, v.id AS id2 --, ST_MakeLine(centre, the_geom) AS geom
--FROM import.substations s
--LEFT JOIN import.powerlines_vertices_pgr v ON ST_DWithin(centre, the_geom, 0.005);
--
--UPDATE import.powerlines l SET source = id1 FROM links WHERE source = id2;
--UPDATE import.powerlines l SET target = id1 FROM links WHERE target = id2;