--################################
--  Import FDW
--################################
DROP SCHEMA IF EXISTS ref_geo CASCADE;
CREATE SCHEMA IF NOT EXISTS ref_geo;

IMPORT FOREIGN SCHEMA ref_geo
	LIMIT TO (ref_geo.l_areas, ref_geo.li_municipalities, ref_geo.bib_areas_types)
    FROM SERVER geonaturedbserver INTO ref_geo ;

--################################
--###COMMUNES
--################################

DO $$
BEGIN
	DROP TABLE atlas.l_communes;
EXCEPTION WHEN others THEN
	RAISE NOTICE 'view atlas.l_communes does not exist';
END$$;


CREATE MATERIALIZED VIEW atlas.l_communes AS
 SELECT c.area_code as insee,
    c.area_name as commune_maj,
    st_transform(c.geom, 3857) as the_geom,
    st_asgeojson(st_transform(c.geom, 4326)) AS commune_geojson
   FROM ref_geo.l_areas c
   JOIN ref_geo.li_municipalities m ON c.id_area = m.id_area
   WHERE enable=true
WITH DATA;


CREATE INDEX index_gist_l_communes_the_geom
  ON atlas.l_communes
  USING gist
  (the_geom);

-- Index: atlas.l_communes_insee_idx

-- DROP INDEX atlas.l_communes_insee_idx;

CREATE UNIQUE INDEX l_communes_insee_idx
  ON atlas.l_communes
  USING btree
  (insee COLLATE pg_catalog."default");

DROP TABLE atlas.l_communes;

--################################
--################################
--###Mailles
--################################
--################################

DO $$
BEGIN
	DROP TABLE atlas.t_mailles_territoire;
EXCEPTION WHEN others THEN
	RAISE NOTICE 'view atlas.t_mailles_territoire does not exist';
END$$;


CREATE MATERIALIZED VIEW atlas.t_mailles_territoire AS
SELECT st_transform(c.geom, 3857) as the_geom,
    st_asgeojson(st_transform(c.geom, 4326)) AS geojson_maille,
    id_area as id_maille
FROM ref_geo.l_areas c
JOIN ref_geo.bib_areas_types t
ON t.id_type = c.id_type
WHERE t.type_code = :type_maille;



--################################
--################################
--###Territoires
--################################
--################################

DO $$
BEGIN
	DROP TABLE atlas.t_layer_territoire;
EXCEPTION WHEN others THEN
	RAISE NOTICE 'view atlas.t_mailles_territoire does not exist';
END$$;


CREATE MATERIALIZED VIEW atlas.t_layer_territoire AS
WITH d AS (
	SELECT st_union(geom) , b.type_name
	FROM ref_geo.l_areas l
	JOIN ref_geo.bib_areas_types b USING(id_type)
	WHERE b.type_code = :type_territoire
	GROUP BY b.type_name
)
SELECT
 1::int as gid,
 type_name as nom,
 st_area(st_union)/10000 as surf_ha,
 st_area(st_union)/1000000 as surf_km2,
 ST_Perimeter(st_union)/1000 as perim_km,
 st_transform(st_union, 3857) as  the_geom
FROM d;



CREATE MATERIALIZED VIEW atlas.vm_communes AS
SELECT c.insee,
c.commune_maj,
c.the_geom,
st_asgeojson(st_transform(c.the_geom, 4326)) as commune_geojson
FROM atlas.l_communes c
JOIN atlas.t_layer_territoire t ON st_intersects(t.the_geom, c.the_geom);




-- Rafraichissement des vues contenant les données de l'atlas
CREATE OR REPLACE FUNCTION atlas.refresh_materialized_view_ref_geo()
RETURNS VOID AS $$
BEGIN
      
  REFRESH MATERIALIZED VIEW atlas.t_layer_territoire;
  REFRESH MATERIALIZED VIEW atlas.t_mailles_territoire;
  REFRESH MATERIALIZED VIEW atlas.l_communes;
  REFRESH MATERIALIZED VIEW atlas.vm_communes;

END
$$ LANGUAGE plpgsql;