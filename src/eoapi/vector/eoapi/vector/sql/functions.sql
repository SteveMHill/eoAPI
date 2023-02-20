-- TODO
-- add function for STAC collections or searchid
-- items MVT (return geojson features)
-- items count (return input geometry + count as MVT)

CREATE OR REPLACE FUNCTION pg_temp.jsonb2timestamptz(j jsonb) RETURNS timestamptz AS $$
    SELECT
        (nullif(j->>0, 'null'))::timestamptz;
$$ LANGUAGE SQL IMMUTABLE STRICT;

CREATE OR REPLACE VIEW pg_temp.pgstac_collections_view AS
SELECT
    id,
    pg_temp.jsonb2timestamptz(content->'extent'->'temporal'->'interval'->0->0) as start_datetime,
    pg_temp.jsonb2timestamptz(content->'extent'->'temporal'->'interval'->0->1) AS end_datetime,
    ST_MakeEnvelope(
        (content->'extent'->'spatial'->'bbox'->0->>0)::float,
        (content->'extent'->'spatial'->'bbox'->0->>1)::float,
        (content->'extent'->'spatial'->'bbox'->0->>2)::float,
        (content->'extent'->'spatial'->'bbox'->0->>3)::float,
        4326
    ) as geom,
    content
FROM pgstac.collections;

CREATE OR REPLACE FUNCTION pg_temp.pgstac_hash(
    IN queryhash text,
    IN bounds geometry DEFAULT ST_MakeEnvelope(-180,-90,180,90,4326),
    -- IN fields jsonb DEFAULT NULL,
    -- IN _scanlimit int DEFAULT 10000,
    -- IN _limit int DEFAULT 100,
    -- IN _timelimit interval DEFAULT '5 seconds'::interval,
    -- IN exitwhenfull boolean DEFAULT TRUE,
    -- IN skipcovered boolean DEFAULT TRUE,
    OUT id text,
    OUT geom geometry,
    OUT content jsonb
) RETURNS SETOF RECORD AS $$
DECLARE
    _scanlimit int := 10000; -- remove if add params back in
    fields jsonb := '{}'::jsonb; -- remove if add params back in
    search searches%ROWTYPE;
    curs refcursor;
    _where text;
    query text;
    iter_record items%ROWTYPE;
    -- out_records jsonb := '{}'::jsonb[];
    -- exit_flag boolean := FALSE;
    -- counter int := 1;
    -- scancounter int := 1;
    remaining_limit int := _scanlimit;
    -- tilearea float;
    -- unionedgeom geometry;
    -- clippedgeom geometry;
    -- unionedgeom_area float := 0;
    -- prev_area float := 0;
    -- excludes text[];
    -- includes text[];

BEGIN

    -- IF skipcovered THEN
    --     exitwhenfull := TRUE;
    -- END IF;

    SELECT * INTO search FROM searches WHERE hash=queryhash;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Search with Query Hash % Not Found', queryhash;
    END IF;

    IF st_srid(bounds) != 4326 THEN
        bounds := ST_Transform(bounds, 4326);
    END IF;

    -- tilearea := st_area(bounds);
    _where := format(
        '%s AND st_intersects(geometry, %L::geometry)',
        search._where,
        bounds
    );


    FOR query IN SELECT * FROM partition_queries(_where, search.orderby) LOOP
        query := format('%s LIMIT %L', query, remaining_limit);
        OPEN curs FOR EXECUTE query;
        LOOP
            FETCH curs INTO iter_record;
            EXIT WHEN NOT FOUND;
            -- IF exitwhenfull OR skipcovered THEN
            --     clippedgeom := st_intersection(geom, iter_record.geometry);

            --     IF unionedgeom IS NULL THEN
            --         unionedgeom := clippedgeom;
            --     ELSE
            --         unionedgeom := st_union(unionedgeom, clippedgeom);
            --     END IF;

            --     unionedgeom_area := st_area(unionedgeom);

            --     IF skipcovered AND prev_area = unionedgeom_area THEN
            --         scancounter := scancounter + 1;
            --         CONTINUE;
            --     END IF;

            --     prev_area := unionedgeom_area;

            -- END IF;

            id := iter_record.id;
            geom := iter_record.geometry;
            content := content_hydrate(iter_record, fields);
            RETURN NEXT;

            -- IF counter >= _limit
            --     OR scancounter > _scanlimit
            --     OR ftime() > _timelimit
            --     OR (exitwhenfull AND unionedgeom_area >= tilearea)
            -- THEN
            --     exit_flag := TRUE;
            --     EXIT;
            -- END IF;
            -- counter := counter + 1;
            -- scancounter := scancounter + 1;

        END LOOP;
        CLOSE curs;
        -- EXIT WHEN exit_flag;
        -- remaining_limit := _scanlimit - scancounter;
    END LOOP;

    RETURN;
END;
$$ LANGUAGE PLPGSQL;
