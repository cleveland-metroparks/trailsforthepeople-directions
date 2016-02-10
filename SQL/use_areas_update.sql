-- After the datasets are uploaded, add the Lat/Lng of its centroid, and its W/S/E/N bounding box, in WGS84.
-- This is used extensively for zooming the map, and for client-side distance calculation.
-- For cm_trails, also add the geometry's length, which is used later for calculating a human-readable length.
delete from cm_use_areas where app = '0';
alter table cm_use_areas add column lat float;
alter table cm_use_areas add column lng float;
alter table cm_use_areas add column lat_dms varchar(15);
alter table cm_use_areas add column lng_dms varchar(15);
alter table cm_use_areas add column boxw float;
alter table cm_use_areas add column boxs float;
alter table cm_use_areas add column boxe float;
alter table cm_use_areas add column boxn float;

update cm_use_areas set lat=ST_Y(ST_TRANSFORM(ST_PointOnSurface(geom),4326));
update cm_use_areas set lng=ST_X(ST_TRANSFORM(ST_PointOnSurface(geom),4326));
update cm_use_areas set lat_dms='N ' || TRUNC(lat) || ' ' || ROUND((60*(lat-TRUNC(lat)))::numeric,3);
update cm_use_areas set lng_dms='W ' || TRUNC(ABS(lng)) || ' ' || ROUND((60*(ABS(lng)-TRUNC(ABS(lng))))::numeric,3);
update cm_use_areas set boxw=ST_XMIN(ST_TRANSFORM(geom,4326));
update cm_use_areas set boxe=ST_XMAX(ST_TRANSFORM(geom,4326));
update cm_use_areas set boxs=ST_YMIN(ST_TRANSFORM(geom,4326));
update cm_use_areas set boxn=ST_YMAX(ST_TRANSFORM(geom,4326));

alter table cm_use_areas add column lat_driving float;
alter table cm_use_areas add column lng_driving float;
update cm_use_areas set lat_driving=lat;
update cm_use_areas set lng_driving=lng;

-- the Use Areas table (cm_use_areas) is polygons, but we really want them cast to points so GeoServer and PostGIS see eye-to-eye
-- use the above-calculated lat,lng and drop the polygon geometry entirely, to form a super simple point layer
-- (there was a buggy behavior, where GeoServer would draw the icon someplace other than where PostGIS would pick a lat,lng )
ALTER TABLE cm_use_areas DROP COLUMN geom;
ALTER TABLE cm_use_areas ADD COLUMN geom geometry(POINT,3734);
UPDATE cm_use_areas SET geom=ST_Transform(ST_SetSRID(ST_MakePoint(lng,lat),4326),3734);

GRANT UPDATE ON cm_use_areas TO trails; -- so we can run the XLSX thingy, see updating_data doc for details


-- The Use Areas table (cm_use_areas) has the wrong field names
-- for the Use Areas' title and for the reservation, and the wrong name for Brookside Reservation and Zoo
-- and is missing a few fields which we'll import later from the XLSX

ALTER TABLE cm_use_areas RENAME COLUMN res TO reservation;
--UPDATE cm_use_areas set reservation='Brookside Reservation and Zoo' WHERE reservation='Brookside Reservation';
--ALTER TABLE cm_use_areas RENAME COLUMN location TO use_area;
ALTER TABLE cm_use_areas ADD COLUMN link varchar(1000);
ALTER TABLE cm_use_areas ADD COLUMN cal_link varchar(1000);
ALTER TABLE cm_use_areas ADD COLUMN image_url varchar(1000);
ALTER TABLE cm_use_areas ADD COLUMN description TEXT;
--ALTER TABLE cm_use_areas ADD COLUMN dest_id INTEGER;

-- The Use Areas table (cm_use_areas) needs the various combinations of activities distilled into
-- a choice of icons. There may be combinations and surprises, but that's why we have the NULL check at the end.
ALTER TABLE cm_use_areas ADD COLUMN icon VARCHAR(50);
UPDATE cm_use_areas SET icon='archery' WHERE activity='Archery' AND show='1';
UPDATE cm_use_areas SET icon='archery' WHERE activity='Archery; Facilities' AND show='1';
UPDATE cm_use_areas SET icon='beach' WHERE activity='Beach' AND show='1';
UPDATE cm_use_areas SET icon='swim' WHERE activity='Swimming; Beach' AND show='1';
UPDATE cm_use_areas SET icon='boat' WHERE activity='Boating' AND show='1';
UPDATE cm_use_areas SET icon='boat' WHERE activity='Boating; Facilities' AND show='1';
UPDATE cm_use_areas SET icon='fish_boat' WHERE activity='Boating; Fishing & Ice Fishing; Swimming; Viewing Wildlife' AND show='1';
UPDATE cm_use_areas SET icon='fish_boat' WHERE activity='Boating; Fishing & Ice Fishing; Viewing Wildlife' AND show='1';
UPDATE cm_use_areas SET icon='fish_boat' WHERE activity='Boating; Fishing & Ice Fishing; Viewing Wildlife; Facilities' AND show='1';
UPDATE cm_use_areas SET icon='food' WHERE activity='Food' AND show='1';
UPDATE cm_use_areas SET icon='history' WHERE activity='Exploring Culture & History' AND show='1';
UPDATE cm_use_areas SET icon='history' WHERE activity='Exploring Culture & History; Facilities' AND show='1';
UPDATE cm_use_areas SET icon='history' WHERE activity='Exploring Culture & History; Sledding & Tobogganing' AND show='1';
UPDATE cm_use_areas SET icon='history' WHERE activity='Exploring Culture & History; Sledding & Tobogganing; Facilities' AND show='1';
UPDATE cm_use_areas SET icon='history' WHERE activity='Exploring Culture & History; Viewing Wildlife' AND show='1';
UPDATE cm_use_areas SET icon='history' WHERE activity='Exploring Culture & History; Viewing Wildlife; Facilities' AND show='1';
UPDATE cm_use_areas SET icon='history' WHERE activity='Drinking Fountain' AND show='1';
UPDATE cm_use_areas SET icon='history' WHERE activity='Drinking Fountain; Exploring Culture & History' AND show='1';
UPDATE cm_use_areas SET icon='history' WHERE activity='Drinking Fountain; Exploring Culture & History; Facilities' AND show='1';
UPDATE cm_use_areas SET icon='history' WHERE activity='Exploring Culture & History; Drinking Fountain; Facilities; Viewing Wildlife' AND show='1';
UPDATE cm_use_areas SET icon='nature' WHERE activity='Exploring Nature' AND show='1';
UPDATE cm_use_areas SET icon='nature_geology' WHERE activity='Exploring Nature; Geologic Feature' AND show='1';
UPDATE cm_use_areas SET icon='fish' WHERE activity='Fishing & Ice Fishing' AND show='1';
UPDATE cm_use_areas SET icon='fish' WHERE activity='Geologic Feature; Fishing & Ice Fishing' AND show='1';
UPDATE cm_use_areas SET icon='fish' WHERE activity='Fishing & Ice Fishing; Viewing Wildlife' AND show='1';
UPDATE cm_use_areas SET icon='geology' WHERE activity='Geologic Feature' AND show='1';
UPDATE cm_use_areas SET icon='golf' WHERE activity='Golfing' AND show='1';
UPDATE cm_use_areas SET icon='horse' WHERE activity='Horseback Riding' AND show='1';
UPDATE cm_use_areas SET icon='horse' WHERE activity='Horseback Riding; Facilities' AND show='1';
UPDATE cm_use_areas SET icon='horse' WHERE activity='Drinking Fountain; Horseback Riding; Facilities' AND show='1';
UPDATE cm_use_areas SET icon='kayak' WHERE activity='Kayaking' AND show='1';
UPDATE cm_use_areas SET icon='picnic' WHERE activity='Picnicking' AND show='1';
UPDATE cm_use_areas SET icon='picnic' WHERE activity='Drinking Fountain; Picnicking' AND show='1';
UPDATE cm_use_areas SET icon='picnic' WHERE activity='Picnicking; Play Areas' AND show='1';
UPDATE cm_use_areas SET icon='picnic' WHERE activity='Picnicking; Play Areas' AND show='1';
UPDATE cm_use_areas SET icon='picnic' WHERE activity='Drinking Fountain; Picnicking; Play Areas' AND show='1';
UPDATE cm_use_areas SET icon='picnic' WHERE activity='Picnicking; Sledding & Tobogganing' AND show='1';
UPDATE cm_use_areas SET icon='play' WHERE activity='Play Area' AND show='1';
UPDATE cm_use_areas SET icon='play' WHERE activity='Play Areas' AND show='1';
UPDATE cm_use_areas SET icon='play' WHERE activity='Drinking Fountain; Play Areas' AND show='1';
UPDATE cm_use_areas SET icon='sled' WHERE activity='Sledding & Tobogganing' AND show='1';
UPDATE cm_use_areas SET icon='swim' WHERE activity='Swimming' AND show='1';
UPDATE cm_use_areas SET icon='wildlife' WHERE activity='Viewing Wildlife' AND show='1';
UPDATE cm_use_areas SET icon='picnic' WHERE activity='Picnicking; Viewing Wildlife' AND show='1';
UPDATE cm_use_areas SET icon='restroom' WHERE activity='Restroom' AND show='1';
UPDATE cm_use_areas SET icon='restroom' WHERE activity='Drinking Fountain; Restroom' AND show='1';
UPDATE cm_use_areas SET icon='food' WHERE activity='Food; Restroom' AND show='1';
UPDATE cm_use_areas SET icon='food' WHERE activity='Food' AND show='1';
--UPDATE cm_use_areas SET icon='reservable' WHERE park_spots='Reserved';
UPDATE cm_use_areas SET icon='reservable' WHERE activity='Picnicking' AND show='1' AND reserved = 'Yes';
UPDATE cm_use_areas SET icon='reservable' WHERE activity='Drinking Fountain; Picnicking' AND show='1' AND reserved = 'Yes';
SELECT DISTINCT activity FROM cm_use_areas WHERE icon IS NULL ORDER BY activity;

-- load the descriptions into cm_use_areas
-- do the import at http://maps.clemetparks.com/static/import/Use_Areas_Descriptions.php

-- Add the tsvector fields for keyword full-text searching.
-- This is used by Ajax::keyword() via each model's searchByKeywords() method
-- A few of the tables have some areas with names that the TS mangles, notably acronyms and initials, so we patch around those

ALTER TABLE cm_use_areas ADD COLUMN search tsvector;
UPDATE cm_use_areas SET search=to_tsvector(coalesce(use_area,'') || ' ' || replace(coalesce(use_area,''),'.',' ') || ' ' || replace(coalesce(use_area,''),'.','') || ' ' || replace(coalesce(use_area,''),'-',' ') || ' ' || replace(coalesce(use_area,''),'-','') || ' ' || coalesce(activity,'') );
CREATE INDEX cm_use_areas_search ON cm_use_areas USING GIN (search);
