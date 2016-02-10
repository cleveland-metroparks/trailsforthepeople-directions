alter table reservation_boundaries_public_private_cm_dissolved add column lat float;
alter table reservation_boundaries_public_private_cm_dissolved add column lng float;
alter table reservation_boundaries_public_private_cm_dissolved add column boxw float;
alter table reservation_boundaries_public_private_cm_dissolved add column boxs float;
alter table reservation_boundaries_public_private_cm_dissolved add column boxe float;
alter table reservation_boundaries_public_private_cm_dissolved add column boxn float;

update reservation_boundaries_public_private_cm_dissolved set lat=ST_Y(ST_TRANSFORM(ST_PointOnSurface(geom),4326));
update reservation_boundaries_public_private_cm_dissolved set lng=ST_X(ST_TRANSFORM(ST_PointOnSurface(geom),4326));
update reservation_boundaries_public_private_cm_dissolved set boxw=ST_XMIN(ST_TRANSFORM(geom,4326));
update reservation_boundaries_public_private_cm_dissolved set boxe=ST_XMAX(ST_TRANSFORM(geom,4326));
update reservation_boundaries_public_private_cm_dissolved set boxs=ST_YMIN(ST_TRANSFORM(geom,4326));
update reservation_boundaries_public_private_cm_dissolved set boxn=ST_YMAX(ST_TRANSFORM(geom,4326));

alter table reservation_boundaries_public_private_cm_dissolved add column lat_driving float;
alter table reservation_boundaries_public_private_cm_dissolved add column lng_driving float;
update reservation_boundaries_public_private_cm_dissolved set lat_driving=lat;
update reservation_boundaries_public_private_cm_dissolved set lng_driving=lng;

alter table reservation_boundaries_public_private_cm_dissolved add column wkt text;
update reservation_boundaries_public_private_cm_dissolved set wkt=ST_ASTEXT(ST_TRANSFORM(geom,4326));

GRANT UPDATE ON reservation_boundaries_public_private_cm_dissolved TO trails; -- so we can load activities from contained Use Areas, see updating_data doc for details

alter table reservation_boundaries_public_private_cm_dissolved rename column res_id TO reservation_id;

alter table reservation_boundaries_public_private_cm_dissolved add column activities text;


-- the Reservations table lacks a "link" field, indicating an external URl for more info about each reservation
-- create it and populate it

ALTER TABLE reservation_boundaries_public_private_cm_dissolved ADD COLUMN link varchar(100);

UPDATE reservation_boundaries_public_private_cm_dissolved SET link='http://www.clevelandmetroparks.com/Main/Reservations-Partners/Bedford-Reservation-1.aspx' WHERE res='Bedford Reservation';
UPDATE reservation_boundaries_public_private_cm_dissolved SET link='http://www.clevelandmetroparks.com/Main/Reservations-Partners/Big-Creek-Reservation-2.aspx' WHERE res='Big Creek Reservation';
UPDATE reservation_boundaries_public_private_cm_dissolved SET link='http://www.clevelandmetroparks.com/Main/Reservations-Partners/Bradley-Woods-Reservation-3.aspx' WHERE res='Bradley Woods Reservation';
UPDATE reservation_boundaries_public_private_cm_dissolved SET link='http://www.clevelandmetroparks.com/Main/Reservations-Partners/Brecksville-Reservation-4.aspx' WHERE res='Brecksville Reservation';
UPDATE reservation_boundaries_public_private_cm_dissolved SET link='http://www.clevelandmetroparks.com/Main/Reservations-Partners/Brookside-Reservation-5.aspx' WHERE res='Brookside Reservation';
UPDATE reservation_boundaries_public_private_cm_dissolved SET link='http://www.clevelandmetroparks.com/Main/Reservations-Partners/Euclid-Creek-Reservation-6.aspx' WHERE res='Euclid Creek Reservation';
UPDATE reservation_boundaries_public_private_cm_dissolved SET link='http://www.clevelandmetroparks.com/Main/Reservations-Partners/Garfield-Park-Reservation-7.aspx' WHERE res='Garfield Park Reservation';
UPDATE reservation_boundaries_public_private_cm_dissolved SET link='http://www.clevelandmetroparks.com/Main/Reservations-Partners/Hinckley-Reservation-8.aspx' WHERE res='Hinckley Reservation';
UPDATE reservation_boundaries_public_private_cm_dissolved SET link='http://www.clevelandmetroparks.com/Main/Reservations-Partners/Huntington-Reservation-9.aspx' WHERE res='Huntington Reservation';
UPDATE reservation_boundaries_public_private_cm_dissolved SET link='http://www.clevelandmetroparks.com/Main/Reservations-Partners/Mill-Stream-Run-Reservation-10.aspx' WHERE res='Mill Stream Run Reservation';
UPDATE reservation_boundaries_public_private_cm_dissolved SET link='http://www.clevelandmetroparks.com/Main/Reservations-Partners/North-Chagrin-Reservation-11.aspx' WHERE res='North Chagrin Reservation';
UPDATE reservation_boundaries_public_private_cm_dissolved SET link='http://www.clevelandmetroparks.com/Main/Reservations-Partners/Ohio-Erie-Canal-Reservation-12.aspx' WHERE res='Ohio & Erie Canal Reservation';
UPDATE reservation_boundaries_public_private_cm_dissolved SET link='http://www.clevelandmetroparks.com/Main/Reservations-Partners/Rocky-River-Reservation-13.aspx' WHERE res='Rocky River Reservation';
UPDATE reservation_boundaries_public_private_cm_dissolved SET link='http://www.clevelandmetroparks.com/Main/Reservations-Partners/South-Chagrin-Reservation-14.aspx' WHERE res='South Chagrin Reservation';
UPDATE reservation_boundaries_public_private_cm_dissolved SET link='http://www.clevelandmetroparks.com/Main/Reservations-Partners/Washington-Reservation-15.aspx' WHERE res='Washington Reservation';
UPDATE reservation_boundaries_public_private_cm_dissolved SET link='http://www.clevelandmetroparks.com/Main/Reservations-Partners/West-Creek-Reservation-16.aspx' WHERE res='West Creek Reservation';
UPDATE reservation_boundaries_public_private_cm_dissolved SET link='http://www.clevelandmetroparks.com/Main/Reservations-Partners/Lakefront-Reservation-18.aspx' WHERE res='Lakefront Reservation';

-- The Reservations table uses char() instead of varchar() fields and adds extra spaces
-- These make text matching difficult, and adds hundreds of trim() calls
ALTER TABLE reservation_boundaries_public_private_cm_dissolved RENAME COLUMN res TO old_res;
ALTER TABLE reservation_boundaries_public_private_cm_dissolved ADD COLUMN res varchar(80);
UPDATE reservation_boundaries_public_private_cm_dissolved SET res=TRIM(both FROM old_res);
ALTER TABLE reservation_boundaries_public_private_cm_dissolved DROP COLUMN old_res;

ALTER TABLE reservation_boundaries_public_private_cm_dissolved ADD COLUMN search tsvector;
UPDATE reservation_boundaries_public_private_cm_dissolved  SET search=to_tsvector(res);
CREATE INDEX reservation_boundaries_public_private_cm_dissolved_search ON reservation_boundaries_public_private_cm_dissolved USING GIN (search);

