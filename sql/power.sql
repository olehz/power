DROP TABLE IF EXISTS import.substations;CREATE TABLE import.substations AS
SELECT
osm_id AS id,
ref,
name,
CASE WHEN TRIM(voltage) ~* '^[0-9;]+$' THEN (SELECT string_agg((t::float/1000)::varchar,'/') FROM UNNEST(string_to_array(TRIM(voltage), ';')) t WHERE t != '') ELSE '' END AS voltage,
CASE WHEN TRIM(voltage) ~* '^[0-9;]+$' THEN (SELECT MAX(t::int) FROM UNNEST(string_to_array(voltage, ';')) t WHERE t != '')/1000 ELSE 0 END AS max_voltage,
rating AS r,
COALESCE(substring(LOWER(TRIM(rating)) FROM '^([0-9\.\,]+)( kva| mva|kva|mva)*$')::float * CASE WHEN substring(LOWER(TRIM(rating)) FROM '^[0-9\.\,]+ (kva|mva)*$') = 'mva' THEN 1000 ELSE 1 END, 0)/1000 AS rating,
--ROUND(ST_AREA(geometry::geography)/100) AS area,
substation,
ST_PointOnSurface(geometry) AS centre,
geometry
FROM import.osm_substations
WHERE substation != 'minor_distribution'
--AND ST_AREA(geometry::geography) > 150
;


DROP TABLE IF EXISTS import.powerplants;CREATE TABLE import.powerplants AS
SELECT
osm_id AS id, name, plant_source, generator_source,
CASE
    WHEN types && ARRAY['hydro','tidal','wave','geothermal'] THEN 'hydro'
    WHEN types && ARRAY['biogas','biofuel','biomass','coal','diesel','gas','gasoline','oil','waste'] THEN 'thermal'
    ELSE plant_source
END AS type,
COALESCE(POWER(10, CASE substring(LOWER(TRIM("power")) FROM '^[0-9\.\,]+ (kw|mw|gw)*$') WHEN 'kw' THEN 3 WHEN 'mw' THEN 6 WHEN 'gw' THEN 9 END) * substring(LOWER(TRIM("power")) FROM '^([0-9\.\,]+) (kw|mw|gw)*$')::float / 1000000, 0) AS mw,
ST_PointOnSurface(geometry) AS centre,
geometry
FROM import.osm_plants
INNER JOIN LATERAL string_to_array(plant_source,';') AS types ON TRUE
WHERE power != '';

DROP TABLE IF EXISTS import.powerlines;CREATE TABLE import.powerlines AS
SELECT
  l.osm_id AS id,
  operator,
  voltage,
  cables,
  circuits,
  wires,
  (disused != '' OR disused_power != '' OR abandoned != '' OR abandoned_power != '') AS disused,
  (v[1] >= 35 AND v[1] < 110) OR (v[2] >= 35 AND v[2] < 110) AS v35,
  (v[1] >= 110 AND v[1] < 150) OR (v[2] >= 110 AND v[2] < 150) AS v110,
  (v[1] >= 150 AND v[1] < 220) OR (v[2] >= 150 AND v[2] < 220) AS v150,
  (v[1] >= 220 AND v[1] < 330) OR (v[2] >= 220 AND v[2] < 330) AS v220,
  (v[1] >= 330 AND v[1] < 400) OR (v[2] >= 330 AND v[2] < 400) AS v330,
  (v[1] >= 400 AND v[1] < 500) OR (v[2] >= 400 AND v[2] < 500) AS v400,
  (v[1] >= 500 AND v[1] < 750) OR (v[2] >= 500 AND v[2] < 750) AS v500,
  (v[1] >= 750) OR (v[2] >= 750) AS v750,
  geometry

FROM import.osm_lines l, import.osm_admin a
INNER JOIN LATERAL (SELECT ARRAY[
    CASE WHEN TRIM(v[1]) ~* '^[0-9;]+$' THEN v[1]::integer/1000 ELSE 0 END,
    CASE WHEN TRIM(v[2]) ~* '^[0-9;]+$' THEN v[2]::integer/1000 ELSE 0 END
    ] AS v FROM string_to_array(TRIM(voltage), ';') AS v
) AS v ON TRUE
WHERE
--country_code='UA' AND (ST_Within(geometry, boundary) OR ST_Intersects(geometry, boundary));
a.name = 'Львівська область' AND (ST_Within(geometry, boundary) OR ST_Intersects(geometry, boundary));

--DELETE FROM import.powerlines WHERE NOT (v35 OR v110 OR v150 OR v220 OR v330 OR v400 OR v500 OR v750 OR voltage = '');

--DELETE FROM import.powerlines WHERE NOT (v35 OR v110 OR v150 OR v220 OR v330 OR v400 OR v500 OR v750);
--DELETE FROM import.powerplants WHERE NOT ST_Within(centre, (SELECT boundary FROM import.osm_admin WHERE name = 'Львівська область'));
--DELETE FROM import.substations WHERE NOT ST_Within(centre, (SELECT boundary FROM import.osm_admin WHERE name = 'Львівська область'));


--UPDATE import.powerlines l SET geometry = z.geometry FROM (
--SELECT l.id AS id, ST_Intersection(geometry, geom) AS geometry
--FROM (SELECT ST_SetSrid(geom, 4326) AS geom FROM admin WHERE id=1) a,
--import.powerlines l
--) z
--WHERE NOT st_isempty(z.geometry) AND l.id = z.id;

ALTER TABLE import.powerlines ADD COLUMN s geometry(POINT,4326), ADD COLUMN e geometry(POINT,4326);
UPDATE import.powerlines SET s = ST_StartPoint(geometry), e = ST_EndPoint(geometry);
CREATE INDEX powerlines_s ON import.powerlines USING GIST(s);
CREATE INDEX powerlines_e ON import.powerlines USING GIST(e);
CLUSTER powerlines_s ON import.powerlines;CLUSTER powerlines_e ON import.powerlines;


INSERT INTO import.powerlines(geometry)
    SELECT ST_MakeLine(e, centre) AS geometry
    FROM import.substations p
    INNER JOIN import.powerlines l ON ST_DWithin(p.geometry, e, 0.0015);


INSERT INTO import.powerlines(geometry)
    SELECT ST_MakeLine(centre, s) AS geometry
    FROM import.substations p
    INNER JOIN import.powerlines l ON ST_DWithin(p.geometry, s, 0.0015);

--
--ALTER TABLE import.substations ADD COLUMN lines bigint[], ADD COLUMN buf geometry;
--UPDATE import.substations SET buf = ST_Buffer(geometry::geography, 50)::geometry;
--UPDATE import.substations s SET lines = COALESCE((SELECT array_agg(p.id) FROM import.powerlines p WHERE p.s && s.buf),'{}')::bigint[];
--UPDATE import.substations s SET lines = lines||COALESCE((SELECT array_agg(p.id) FROM import.powerlines p WHERE p.e && s.buf),'{}')::bigint[];
--
--ALTER TABLE import.powerlines DROP COLUMN s, DROP COLUMN e;
--ALTER TABLE import.substations DROP COLUMN buf;