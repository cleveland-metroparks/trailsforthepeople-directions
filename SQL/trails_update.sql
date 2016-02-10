--RUN AFTER LOADING A NEW 'TRAILS' DATAESET (cm_trails.shp)

CREATE INDEX cm_trails_geom ON cm_trails USING GIST (geom);

ALTER TABLE cm_trails ADD COLUMN length float;
UPDATE cm_trails SET length = ST_LENGTH(geom);

alter table cm_trails add column lat float;
alter table cm_trails add column lng float;
alter table cm_trails add column boxw float;
alter table cm_trails add column boxs float;
alter table cm_trails add column boxe float;
alter table cm_trails add column boxn float;

update cm_trails set lat=ST_Y(ST_CENTROID(ST_TRANSFORM(geom,4326)));
update cm_trails set lng=ST_X(ST_CENTROID(ST_TRANSFORM(geom,4326)));
update cm_trails set boxw=ST_XMIN(ST_TRANSFORM(geom,4326));
update cm_trails set boxe=ST_XMAX(ST_TRANSFORM(geom,4326));
update cm_trails set boxs=ST_YMIN(ST_TRANSFORM(geom,4326));
update cm_trails set boxn=ST_YMAX(ST_TRANSFORM(geom,4326));

GRANT UPDATE ON trails_fixed TO trails; -- so we can run the XLSX thingy, see updating_data doc for details

ALTER TABLE cm_trails ADD COLUMN search tsvector;
UPDATE cm_trails SET search=to_tsvector( coalesce(label_name,'') );
CREATE INDEX cm_trails_search ON cm_trails USING GIN (search);


-- Data fixes for the trails: Paved vs Unpaved, allow Hike to cross roads, add mean elevation to each trail

-- for routing preferences, we need to know whether a trail is paved (paved=Yes) or natural (paved=No)
-- The following sets this based on the "surfacetyp" and may need adjustments with each new revision of the data,
-- to account for typos, new types, etc.
-- Some types are left intentionally null so they fit into both categories, notably bridges and boardwalks

ALTER TABLE cm_trails ADD COLUMN paved varchar(3);
UPDATE cm_trails SET paved='No' WHERE surface = 'Unpaved';
UPDATE cm_trails SET paved='Yes' WHERE surface = 'Paved';

-- Hiking is too restricted; a hiker can't even cross a street.
-- This accounts for that, by presuming that any bike-friendly street also has a sidewalk.

--UPDATE cm_trails SET hike='Yes' where pri_use='Road' AND bike='Yes';

-- Mountain Biking

--ALTER TABLE cm_trails ADD COLUMN mtnbike varchar(5);
--UPDATE cm_trails SET mtnbike='No';

--UPDATE cm_trails SET mtnbike='Yes', bike='No', one_way=NULL WHERE
--   ( for_show='Yes' AND res LIKE '%Mill Stream%' AND label_name LIKE '%Red%' )
--    OR
--    ( for_show='Yes' AND res  LIKE '%Mill Stream%' AND label_name LIKE '%Yellow%' )
--    OR
--    ( for_show='Yes' AND res ='Ohio & Erie Canal Reservation'AND label_name LIKE '%Ohio & Erie Canal Reservation Mountain Bike Trail%' )
--;


-- Add elevation data to the cm_trails so it can be click-queried
-- Less accurate than what's in the smaller chunks of the routing table, but it's what there is for click-queries
ALTER TABLE cm_trails ADD COLUMN elevation integer;
UPDATE cm_trails SET elevation=ROUND( ST_Z(ST_StartPoint(ST_GeometryN(geom,1))) + ST_Z(ST_EndPoint(ST_GeometryN(geom,1))) ) / 2.0;


-- Now the routing stuff, a project in itself!
-- Create a new table of the trails for routing purposes:  routing_trails
-- * Verified bug in PostGIS 2.0, multilinestring doesn't work with ST_StartPoint() and ST_EndPoint()
-- * Besides, these multilines in fact have 1 component: a single linestring, so it doesn't even make sense that they're multis
-- * Clip the the multiline segments WHICH ARE NOT BRIDGES to 100-foot segments, but leave the bridge=above segments whole.
--   The existing segments are so long that intersection nodes (A*, Dijkstra) are far from real-world destinations, so routing will badly overshoot the target.
-- * pgRouting demands that the geometry field be named the_geom, ours is not, so the routing_trails table uses the_geom.
-- * Side note: original loading method pulled each single linestring from cm_trails. This is now over 3,000,000 records. Don't do that!
-- Create and index a bunch of boolean columns for the Bike/Hike/Bridle/Road attributes.
-- * Turns out that IS NULL queries are much faster than bike='Yes' or even can_bike=true
-- Add the x1 x2 y1 y2 columns for A-Star routing.
-- Add the Cost and Reverse Cost fields.
-- Add the elevation field, for generating elevation profile charts.
-- Add the Lat Lng, etc. for zooming the map and figuring distance from GPS.
-- Add time estimates for traversing each segment, using Tobler's hiking function to define duration_hike, and then multipliers for bike and bridle
-- * The Tobler stuff can't be done in a single step, due to internal PostgreSQL issues causing underflows.
-- * Tobler's algorithm starts with the "6" and yields kilometers per hour, the 0.911344 multiplier is to get feet per second.
-- Keep the vertices_tmp table, so we can render the node points via GeoServer
-- A PL/PGSQL function which will update the "links" field in routing_trails, so we can later filter by nodes with 3+ links (intersections).
-- Lastly, create some views of the trails table, showing only hike, bike, bridle and subcategories thereof

DROP TABLE routing_trails CASCADE;
CREATE TABLE routing_trails (
    gid serial,
    name varchar(150),
    links integer,
    bridge     varchar(5),
    one_way    varchar(2),
    bike       varchar(3),
    bridle     varchar(3),
    hike       varchar(3),
    mtnbike    varchar(3),
    difficulty varchar(20),
    paved      varchar(3),
    pri_use    varchar(25),
    duration_hike    float,
    duration_bike    float,
    duration_bridle  float,
    primary key (gid)
);
SELECT addgeometrycolumn('','routing_trails','the_geom',3734, 'LINESTRING', 3);
CREATE INDEX routing_trails_the_geom ON routing_trails USING GIST (the_geom);

GRANT update ON routing_trails TO trails;

INSERT INTO routing_trails (name, bridge, difficulty, bike, mtnbike, bridle, hike, paved, pri_use, one_way, the_geom)
    SELECT label_name AS name, bridge, skill_cm AS difficulty, bike, mtnbike, bridle, hike, paved, pri_use, one_way, ST_GeometryN(geom,1)
    FROM cm_trails
    WHERE bridge IS NOT NULL;

INSERT INTO routing_trails (name, bridge, difficulty, bike, mtnbike, bridle, hike, paved, pri_use, one_way, the_geom)
    SELECT name, bridge, difficulty, bike, mtnbike, bridle, hike, paved, pri_use, one_way, 
        ST_Line_Substring(t.geometry, 100.0*n/length,
        CASE
        WHEN 100.0*(n+1) < length THEN 100.0*(n+1)/length
        ELSE 1
        END) AS geometry
FROM
   (SELECT label_name AS name, bridge, skill_cm AS difficulty, bike, mtnbike, bridle, hike, paved, pri_use, one_way, 
    length,
    ST_GeometryN(geom,1) AS geometry
    FROM cm_trails
    WHERE bridge IS NULL
    ) t
CROSS JOIN generate_series(0,1000) n
WHERE n*100.00/length < 1;

ALTER TABLE routing_trails ADD COLUMN closed boolean;
CREATE INDEX routing_trails_idx_closed on routing_trails (closed);

ALTER TABLE routing_trails ADD COLUMN is_road boolean;
ALTER TABLE routing_trails ADD COLUMN no_hike boolean;
ALTER TABLE routing_trails ADD COLUMN no_bike boolean;
ALTER TABLE routing_trails ADD COLUMN no_bridle boolean;
ALTER TABLE routing_trails ADD COLUMN no_paved   boolean;
ALTER TABLE routing_trails ADD COLUMN no_unpaved boolean;
UPDATE routing_trails SET is_road=true    WHERE pri_use='Road';
UPDATE routing_trails SET no_hike=true    WHERE hike != 'Yes';
UPDATE routing_trails SET no_bike=true    WHERE bike != 'Yes';
UPDATE routing_trails SET no_bridle=true  WHERE bridle != 'Yes';
UPDATE routing_trails SET no_paved=false   WHERE paved='Yes';
UPDATE routing_trails SET no_unpaved=false WHERE paved='No';
CREATE INDEX routing_trails_idx_is_road    on routing_trails (is_road);
CREATE INDEX routing_trails_idx_no_hike    on routing_trails (no_hike);
CREATE INDEX routing_trails_idx_no_bike    on routing_trails (no_bike);
CREATE INDEX routing_trails_idx_no_bridle  on routing_trails (no_bridle);
CREATE INDEX routing_trails_idx_no_paved   on routing_trails (no_paved);
CREATE INDEX routing_trails_idx_no_unpaved on routing_trails (no_unpaved);

ALTER TABLE routing_trails ADD COLUMN x FLOAT;
ALTER TABLE routing_trails ADD COLUMN y FLOAT;
ALTER TABLE routing_trails ADD COLUMN lat FLOAT;
ALTER TABLE routing_trails ADD COLUMN lng FLOAT;
UPDATE routing_trails SET x=ST_X(ST_CENTROID(the_geom));
UPDATE routing_trails SET y=ST_Y(ST_CENTROID(the_geom));
UPDATE routing_trails SET lng=ST_X(ST_CENTROID(ST_TRANSFORM(the_geom,4326)));
UPDATE routing_trails SET lat=ST_Y(ST_CENTROID(ST_TRANSFORM(the_geom,4326)));

ALTER TABLE routing_trails ADD COLUMN x1 float;
ALTER TABLE routing_trails ADD COLUMN y1 float;
ALTER TABLE routing_trails ADD COLUMN x2 float;
ALTER TABLE routing_trails ADD COLUMN y2 float;
UPDATE routing_trails SET x1 = ST_X(ST_StartPoint(the_geom));
UPDATE routing_trails SET y1 = ST_Y(ST_StartPoint(the_geom));
UPDATE routing_trails SET x2 = ST_X(ST_EndPoint(the_geom));
UPDATE routing_trails SET y2 = ST_Y(ST_EndPoint(the_geom));

ALTER TABLE routing_trails ADD COLUMN length float;
ALTER TABLE routing_trails ADD COLUMN reverse_cost double precision;
UPDATE routing_trails SET length=ST_Length(the_geom);

ALTER TABLE routing_trails ADD COLUMN cost_hike double precision;
UPDATE routing_trails SET cost_hike=length * 2.0 WHERE pri_use='All Purpose Trail';
UPDATE routing_trails SET cost_hike=length * 3.0 WHERE paved='Yes';
UPDATE routing_trails SET cost_hike=length * 6.0 WHERE pri_use='Road';
UPDATE routing_trails SET cost_hike=length WHERE cost_hike IS NULL;

ALTER TABLE routing_trails ADD COLUMN cost_bike double precision;
UPDATE routing_trails SET cost_bike=length * 3 WHERE pri_use!='All Purpose Trail' AND pri_use!='Mountain Biking';
UPDATE routing_trails SET cost_bike=length * 6.0 WHERE pri_use='Road';
UPDATE routing_trails SET cost_bike=length * 6.0 WHERE pri_use='Road Crossing';
UPDATE routing_trails SET cost_bike=length * 6.0 WHERE pri_use='Parking';
UPDATE routing_trails SET cost_bike=length WHERE cost_bike IS NULL;

ALTER TABLE routing_trails ADD COLUMN cost_bridle double precision;
UPDATE routing_trails SET cost_bridle=length * 3 WHERE pri_use!='Bridle';
UPDATE routing_trails SET cost_bridle=length * 6.0 WHERE pri_use='Road';
UPDATE routing_trails SET cost_bridle=length WHERE cost_bridle IS NULL;

UPDATE routing_trails SET cost_hike=999999999   WHERE one_way='FT';
UPDATE routing_trails SET cost_bike=999999999   WHERE one_way='FT';
UPDATE routing_trails SET cost_bridle=999999999 WHERE one_way='FT';
UPDATE routing_trails SET reverse_cost=length;
UPDATE routing_trails SET reverse_cost=999999999 WHERE one_way='TF';

ALTER TABLE routing_trails ADD COLUMN elevation integer;
UPDATE routing_trails SET elevation=ROUND( ST_Z(ST_StartPoint(the_geom)) + ST_Z(ST_EndPoint(the_geom)) ) / 2.0;

ALTER TABLE routing_trails ADD COLUMN tobler_fps FLOAT;
UPDATE routing_trails SET tobler_fps = 0.911344 * 6 * EXP(-3.5 * ABS( (ST_Z(ST_StartPoint(the_geom)) - ST_Z(ST_EndPoint(the_geom)))/length ) );
UPDATE routing_trails SET duration_hike   = length / tobler_fps;
UPDATE routing_trails SET duration_bike   = duration_hike * 0.33;
UPDATE routing_trails SET duration_bridle = duration_hike * 0.80;

ALTER TABLE routing_trails ADD COLUMN "source" integer;
ALTER TABLE routing_trails ADD COLUMN "target" integer;
CREATE INDEX routing_trails_source ON routing_trails ("source");
CREATE INDEX routing_trails_target ON routing_trails ("target");

DROP TABLE IF EXISTS vertices_tmp;
UPDATE routing_trails SET "source"=null;
UPDATE routing_trails SET "target"=null;
SELECT assign_vertex_id('routing_trails', 9, 'the_geom', 'gid');
ANALYZE routing_trails;

ALTER TABLE vertices_tmp ADD COLUMN links integer;
UPDATE vertices_tmp SET links=0;
UPDATE vertices_tmp SET links=vertices_tmp.links+1 FROM routing_trails WHERE routing_trails.source=vertices_tmp.id;
UPDATE vertices_tmp SET links=vertices_tmp.links+1 FROM routing_trails WHERE routing_trails.target=vertices_tmp.id;

SELECT update_routing_trails_link_count();

SELECT update_trail_closures();

CREATE OR REPLACE VIEW routing_trails_hike                       AS SELECT *, cost_hike AS cost FROM routing_trails WHERE closed IS NULL AND no_hike IS NULL;
CREATE OR REPLACE VIEW routing_trails_bridle                     AS SELECT *, cost_bridle AS cost FROM routing_trails WHERE closed IS NULL AND no_bridle IS NULL;
CREATE OR REPLACE VIEW routing_trails_bike                       AS SELECT *, cost_bike AS cost FROM routing_trails WHERE closed IS NULL AND no_bike IS NULL;
CREATE OR REPLACE VIEW routing_trails_hike_paved                 AS SELECT *, cost_hike AS cost FROM routing_trails WHERE closed IS NULL AND no_hike IS NULL and no_unpaved IS NULL;
CREATE OR REPLACE VIEW routing_trails_hike_unpaved               AS SELECT *, cost_hike AS cost FROM routing_trails WHERE closed IS NULL AND no_hike IS NULL and no_paved   IS NULL;
CREATE OR REPLACE VIEW routing_trails_bridle_paved               AS SELECT *, cost_bridle AS cost FROM routing_trails WHERE closed IS NULL AND no_bridle IS NULL and no_unpaved IS NULL;
CREATE OR REPLACE VIEW routing_trails_bridle_unpaved             AS SELECT *, cost_bridle AS cost FROM routing_trails WHERE closed IS NULL AND no_bridle IS NULL and no_paved   IS NULL;
CREATE OR REPLACE VIEW routing_trails_bike_novice                AS SELECT *, cost_bike AS cost FROM routing_trails WHERE closed IS NULL AND no_bike IS NULL AND difficulty IN ('Novice');
CREATE OR REPLACE VIEW routing_trails_bike_beginner              AS SELECT *, cost_bike AS cost FROM routing_trails WHERE closed IS NULL AND no_bike IS NULL AND difficulty IN ('Novice','Beginner');
CREATE OR REPLACE VIEW routing_trails_bike_intermediate          AS SELECT *, cost_bike AS cost FROM routing_trails WHERE closed IS NULL AND no_bike IS NULL AND difficulty != 'Advanced';
CREATE OR REPLACE VIEW routing_trails_bike_advanced              AS SELECT *, cost_bike AS cost FROM routing_trails WHERE closed IS NULL AND no_bike IS NULL;
CREATE OR REPLACE VIEW routing_trails_bike_novice_paved          AS SELECT *, cost_bike AS cost FROM routing_trails WHERE closed IS NULL AND no_bike IS NULL AND difficulty IN ('Novice') and no_unpaved IS NULL;
CREATE OR REPLACE VIEW routing_trails_bike_beginner_paved        AS SELECT *, cost_bike AS cost FROM routing_trails WHERE closed IS NULL AND no_bike IS NULL AND difficulty IN ('Novice','Beginner') and no_unpaved IS NULL;
CREATE OR REPLACE VIEW routing_trails_bike_intermediate_paved    AS SELECT *, cost_bike AS cost FROM routing_trails WHERE closed IS NULL AND no_bike IS NULL AND difficulty != 'Advanced' and no_unpaved IS NULL;
CREATE OR REPLACE VIEW routing_trails_bike_advanced_paved        AS SELECT *, cost_bike AS cost FROM routing_trails WHERE closed IS NULL AND no_bike IS NULL and no_unpaved IS NULL;
CREATE OR REPLACE VIEW routing_trails_bike_novice_unpaved        AS SELECT *, cost_bike AS cost FROM routing_trails WHERE closed IS NULL AND no_bike IS NULL AND difficulty IN ('Novice') and no_paved   IS NULL;
CREATE OR REPLACE VIEW routing_trails_bike_beginner_unpaved      AS SELECT *, cost_bike AS cost FROM routing_trails WHERE closed IS NULL AND no_bike IS NULL AND difficulty IN ('Novice','Beginner') and no_paved   IS NULL;
CREATE OR REPLACE VIEW routing_trails_bike_intermediate_unpaved  AS SELECT *, cost_bike AS cost FROM routing_trails WHERE closed IS NULL AND no_bike IS NULL AND difficulty != 'Advanced' and no_paved   IS NULL;
CREATE OR REPLACE VIEW routing_trails_bike_advanced_unpaved      AS SELECT *, cost_bike AS cost FROM routing_trails WHERE closed IS NULL AND no_bike IS NULL and no_paved   IS NULL;

CREATE OR REPLACE VIEW routing_trails_hike_fastest                       AS SELECT *, duration_hike AS cost FROM routing_trails WHERE closed IS NULL AND no_hike IS NULL;
CREATE OR REPLACE VIEW routing_trails_bridle_fastest                     AS SELECT *, duration_bridle AS cost FROM routing_trails WHERE closed IS NULL AND no_bridle IS NULL;
CREATE OR REPLACE VIEW routing_trails_bike_fastest                       AS SELECT *, duration_bike AS cost FROM routing_trails WHERE closed IS NULL AND no_bike IS NULL;
CREATE OR REPLACE VIEW routing_trails_hike_paved_fastest                 AS SELECT *, duration_hike AS cost FROM routing_trails WHERE closed IS NULL AND no_hike IS NULL and no_unpaved IS NULL;
CREATE OR REPLACE VIEW routing_trails_hike_unpaved_fastest               AS SELECT *, duration_hike AS cost FROM routing_trails WHERE closed IS NULL AND no_hike IS NULL and no_paved   IS NULL;
CREATE OR REPLACE VIEW routing_trails_bridle_paved_fastest               AS SELECT *, duration_bridle AS cost FROM routing_trails WHERE closed IS NULL AND no_bridle IS NULL and no_unpaved IS NULL;
CREATE OR REPLACE VIEW routing_trails_bridle_unpaved_fastest             AS SELECT *, duration_bridle AS cost FROM routing_trails WHERE closed IS NULL AND no_bridle IS NULL and no_paved   IS NULL;
CREATE OR REPLACE VIEW routing_trails_bike_novice_fastest                AS SELECT *, duration_bike AS cost FROM routing_trails WHERE closed IS NULL AND no_bike IS NULL AND difficulty IN ('Novice');
CREATE OR REPLACE VIEW routing_trails_bike_beginner_fastest              AS SELECT *, duration_bike AS cost FROM routing_trails WHERE closed IS NULL AND no_bike IS NULL AND difficulty IN ('Novice','Beginner');
CREATE OR REPLACE VIEW routing_trails_bike_intermediate_fastest          AS SELECT *, duration_bike AS cost FROM routing_trails WHERE closed IS NULL AND no_bike IS NULL AND difficulty != 'Advanced';
CREATE OR REPLACE VIEW routing_trails_bike_advanced_fastest              AS SELECT *, duration_bike AS cost FROM routing_trails WHERE closed IS NULL AND no_bike IS NULL;
CREATE OR REPLACE VIEW routing_trails_bike_novice_paved_fastest          AS SELECT *, duration_bike AS cost FROM routing_trails WHERE closed IS NULL AND no_bike IS NULL AND difficulty IN ('Novice') and no_unpaved IS NULL;
CREATE OR REPLACE VIEW routing_trails_bike_beginner_paved_fastest        AS SELECT *, duration_bike AS cost FROM routing_trails WHERE closed IS NULL AND no_bike IS NULL AND difficulty IN ('Novice','Beginner') and no_unpaved IS NULL;
CREATE OR REPLACE VIEW routing_trails_bike_intermediate_paved_fastest    AS SELECT *, duration_bike AS cost FROM routing_trails WHERE closed IS NULL AND no_bike IS NULL AND difficulty != 'Advanced' and no_unpaved IS NULL;
CREATE OR REPLACE VIEW routing_trails_bike_advanced_paved_fastest        AS SELECT *, duration_bike AS cost FROM routing_trails WHERE closed IS NULL AND no_bike IS NULL and no_unpaved IS NULL;
CREATE OR REPLACE VIEW routing_trails_bike_novice_unpaved_fastest        AS SELECT *, duration_bike AS cost FROM routing_trails WHERE closed IS NULL AND no_bike IS NULL AND difficulty IN ('Novice') and no_paved   IS NULL;
CREATE OR REPLACE VIEW routing_trails_bike_beginner_unpaved_fastest      AS SELECT *, duration_bike AS cost FROM routing_trails WHERE closed IS NULL AND no_bike IS NULL AND difficulty IN ('Novice','Beginner') and no_paved   IS NULL;
CREATE OR REPLACE VIEW routing_trails_bike_intermediate_unpaved_fastest  AS SELECT *, duration_bike AS cost FROM routing_trails WHERE closed IS NULL AND no_bike IS NULL AND difficulty != 'Advanced' and no_paved   IS NULL;
CREATE OR REPLACE VIEW routing_trails_bike_advanced_unpaved_fastest      AS SELECT *, duration_bike AS cost FROM routing_trails WHERE closed IS NULL AND no_bike IS NULL and no_paved   IS NULL;

CREATE OR REPLACE VIEW routing_trails_hike_shortest                       AS SELECT *, length AS cost FROM routing_trails WHERE closed IS NULL AND no_hike IS NULL;
CREATE OR REPLACE VIEW routing_trails_bridle_shortest                     AS SELECT *, length AS cost FROM routing_trails WHERE closed IS NULL AND no_bridle IS NULL;
CREATE OR REPLACE VIEW routing_trails_bike_shortest                       AS SELECT *, length AS cost FROM routing_trails WHERE closed IS NULL AND no_bike IS NULL;
CREATE OR REPLACE VIEW routing_trails_hike_paved_shortest                 AS SELECT *, length AS cost FROM routing_trails WHERE closed IS NULL AND no_hike IS NULL and no_unpaved IS NULL;
CREATE OR REPLACE VIEW routing_trails_hike_unpaved_shortest               AS SELECT *, length AS cost FROM routing_trails WHERE closed IS NULL AND no_hike IS NULL and no_paved   IS NULL;
CREATE OR REPLACE VIEW routing_trails_bridle_paved_shortest               AS SELECT *, length AS cost FROM routing_trails WHERE closed IS NULL AND no_bridle IS NULL and no_unpaved IS NULL;
CREATE OR REPLACE VIEW routing_trails_bridle_unpaved_shortest             AS SELECT *, length AS cost FROM routing_trails WHERE closed IS NULL AND no_bridle IS NULL and no_paved   IS NULL;
CREATE OR REPLACE VIEW routing_trails_bike_novice_shortest                AS SELECT *, length AS cost FROM routing_trails WHERE closed IS NULL AND no_bike IS NULL AND difficulty IN ('Novice');
CREATE OR REPLACE VIEW routing_trails_bike_beginner_shortest              AS SELECT *, length AS cost FROM routing_trails WHERE closed IS NULL AND no_bike IS NULL AND difficulty IN ('Novice','Beginner');
CREATE OR REPLACE VIEW routing_trails_bike_intermediate_shortest          AS SELECT *, length AS cost FROM routing_trails WHERE closed IS NULL AND no_bike IS NULL AND difficulty != 'Advanced';
CREATE OR REPLACE VIEW routing_trails_bike_advanced_shortest              AS SELECT *, length AS cost FROM routing_trails WHERE closed IS NULL AND no_bike IS NULL;
CREATE OR REPLACE VIEW routing_trails_bike_novice_paved_shortest          AS SELECT *, length AS cost FROM routing_trails WHERE closed IS NULL AND no_bike IS NULL AND difficulty IN ('Novice') and no_unpaved IS NULL;
CREATE OR REPLACE VIEW routing_trails_bike_beginner_paved_shortest        AS SELECT *, length AS cost FROM routing_trails WHERE closed IS NULL AND no_bike IS NULL AND difficulty IN ('Novice','Beginner') and no_unpaved IS NULL;
CREATE OR REPLACE VIEW routing_trails_bike_intermediate_paved_shortest    AS SELECT *, length AS cost FROM routing_trails WHERE closed IS NULL AND no_bike IS NULL AND difficulty != 'Advanced' and no_unpaved IS NULL;
CREATE OR REPLACE VIEW routing_trails_bike_advanced_paved_shortest        AS SELECT *, length AS cost FROM routing_trails WHERE closed IS NULL AND no_bike IS NULL and no_unpaved IS NULL;
CREATE OR REPLACE VIEW routing_trails_bike_novice_unpaved_shortest        AS SELECT *, length AS cost FROM routing_trails WHERE closed IS NULL AND no_bike IS NULL AND difficulty IN ('Novice') and no_paved   IS NULL;
CREATE OR REPLACE VIEW routing_trails_bike_beginner_unpaved_shortest      AS SELECT *, length AS cost FROM routing_trails WHERE closed IS NULL AND no_bike IS NULL AND difficulty IN ('Novice','Beginner') and no_paved   IS NULL;
CREATE OR REPLACE VIEW routing_trails_bike_intermediate_unpaved_shortest  AS SELECT *, length AS cost FROM routing_trails WHERE closed IS NULL AND no_bike IS NULL AND difficulty != 'Advanced' and no_paved   IS NULL;
CREATE OR REPLACE VIEW routing_trails_bike_advanced_unpaved_shortest      AS SELECT *, length AS cost FROM routing_trails WHERE closed IS NULL AND no_bike IS NULL and no_paved   IS NULL;


-- And now that we have loaded new trails, purge the trails_fixed table which stores a nice list of Trails With Names
-- So we can list trails of mention, but not list every single irrelevant connecting or bridle trail
-- Load this from cm_trails using a PHP script which reads from a XLSX
-- This allows Cleveland Metworkparks to edit trails, and for us to regenerate this listing.

GRANT UPDATE ON trails_fixed TO trails;
-- do the import at http://maps.clemetparks.com/static/import/Aggregate_Trails.php
SELECT description FROM trails_fixed limit 3;