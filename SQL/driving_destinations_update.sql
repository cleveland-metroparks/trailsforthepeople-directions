alter table driving_destinations rename column res_id TO reservation_id;

alter table driving_destinations add column lat float;
alter table driving_destinations add column lng float;

update driving_destinations set lat=ST_Y(ST_TRANSFORM(ST_PointOnSurface(geom),4326));
update driving_destinations set lng=ST_X(ST_TRANSFORM(ST_PointOnSurface(geom),4326));

