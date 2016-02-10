## Spreadsheets -
* Must reside here: /var/www/static/import

## Shapefiles - Migrate to server and load to database with shp2pgsql commands:
```BASH
shp2pgsql -W LATIN1 -d -i -s 3734 cm_poi.shp cm_use_areas | psql -U postgres path
shp2pgsql -W LATIN1 -d -i -s 3734 cm_destination_pts.shp driving_destinations | psql -U postgres path
shp2pgsql -W LATIN1 -d -i -s 3734 -t 3DZ cm_trails.shp cm_trails | psql -U postgres path
shp2pgsql -W LATIN1 -d -i -s 3734 reservations.shp reservation_boundaries_public_private_cm_dissolved | psql -U postgres path
```

## SQL - Run with psql after loading shapefiles to database
* Trails takes a while (hour or so) to create the routing network
* Shapefiles and driving destinations go very fast

## Run PHP Scripts -
* Best outlined in documentation here: https://maps.clevelandmetroparks.com/docs/index/updating_data


