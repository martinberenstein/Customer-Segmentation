-- Calculate the average number of page clicks for all sessions
SELECT AVG(page_clicks) FROM sessions;

-- Find the shortest session time among sessions with bookings (flight or hotel)
SELECT (session_end - session_start) AS session_time
FROM sessions
WHERE flight_booked = True OR hotel_booked = True
ORDER BY session_time ASC
LIMIT 1;

-- Calculate statistical values for hotel room prices in the "hotels" table
SELECT 
    stddev(hotels.hotel_per_room_usd) AS stdv, -- Calculate standard deviation
    MIN(hotels.hotel_per_room_usd) AS min,     -- Find the minimum room price
    MAX(hotels.hotel_per_room_usd) AS max,     -- Find the maximum room price
    AVG(hotels.hotel_per_room_usd) AS avg_price_room -- Calculate the average room price
FROM hotels;

-- Calculate the average price per room by destination, filtering out outliers
SELECT AVG(hotel_per_room_usd) AS avg_price_room, flights.destination 
FROM hotels
FULL JOIN flights ON hotels.trip_id = flights.trip_id
WHERE hotel_per_room_usd < 411 -- Filter out prices greater than 411 (an outlier)
GROUP BY destination
ORDER BY avg_price_room ASC;

-- Retrieve session length and clicks for sessions without flight or hotel bookings
SELECT page_clicks, (session_end - session_start) AS session_time
FROM sessions
WHERE flight_booked = False AND hotel_booked = False 
ORDER BY session_time DESC;

-- Calculate the proportion of discount offers for flights and hotels
SELECT 
    SUM(CASE WHEN flight_discount THEN 1 ELSE 0 END)::FLOAT / SUM(CASE WHEN flight_booked THEN 1 ELSE 0 END)::FLOAT AS discount_flight_proportion,
    SUM(CASE WHEN hotel_discount THEN 1 ELSE 0 END)::FLOAT / SUM(CASE WHEN hotel_booked THEN 1 ELSE 0 END)::FLOAT AS discount_hotel_proportion
FROM sessions;

-- Calculate the average flight and hotel discounts
SELECT AVG(flight_discount_amount) AS avg_flight_discount, AVG(hotel_discount_amount) AS avg_hotel_discount
FROM sessions;

-- Calculate conversion rates for overall, hotel, and flight bookings
SELECT 
    SUM(CASE WHEN hotel_booked OR flight_booked THEN 1 ELSE 0 END)::FLOAT / COUNT(*) AS overall_conversion_rate,
    SUM(CASE WHEN hotel_booked THEN 1 ELSE 0 END)::FLOAT / COUNT(*) AS hotel_conversion_rate,
    SUM(CASE WHEN flight_booked THEN 1 ELSE 0 END)::FLOAT / COUNT(*) AS flight_conversion_rate
FROM sessions;

-- Calculate the Haversine distance between LAX and JFK airports
WITH lax AS 
(
    SELECT 
        destination_airport_lat AS lat1, 
        destination_airport_lon AS lon1
    FROM flights
    WHERE destination_airport = 'LAX'
  	LIMIT 1
),
jfk AS 
(
    SELECT 
        destination_airport_lat AS lat2, 
        destination_airport_lon AS lon2
    FROM flights
    WHERE destination_airport = 'JFK'
    LIMIT 1
)

SELECT
    6371 * 2 * ASIN(
        SQRT(
            POWER(SIN(RADIANS((lat2 - lat1) / 2)), 2) +
            COS(RADIANS(lat1)) * COS(RADIANS(lat2)) * POWER(SIN(RADIANS((lon2 - lon1) / 2)), 2)
        )
    ) AS distance_in_km
FROM
    lax
CROSS JOIN
    jfk;

-- Calculate the total distance traveled by users based on session data
WITH table_distance AS (
    SELECT 
        u.user_id,
        f.trip_id,
        6371 * 2 * ASIN(
            SQRT(
                POWER(SIN(RADIANS((f.destination_airport_lat - u.home_airport_lat) / 2)), 2) +
                COS(RADIANS(u.home_airport_lat)) * COS(RADIANS(f.destination_airport_lat)) * POWER(SIN(RADIANS((f.destination_airport_lon - u.home_airport_lon) / 2)), 2)
            )
        ) AS distance_in_km
    FROM
        users u
    JOIN
        sessions s ON u.user_id = s.user_id
    JOIN
        flights f ON s.trip_id = f.trip_id
    WHERE
        s.session_start >= '2023-01-04'::DATE
),
kilometers AS (
    SELECT 
        user_id,
        SUM(distance_in_km) AS sum_distance_in_km,
        AVG(distance_in_km) AS avg_distance_in_km
    FROM
        table_distance
    GROUP BY
        user_id
)

-- Retrieve cohort with behavorial metrics
SELECT
    u.user_id,
    u.gender,
    u.married,
    u.has_children,
    u.home_country,
    u.home_city,
    u.home_airport,
    ROUND(AVG(EXTRACT(YEAR FROM AGE(s.session_start, u.birthdate))), 1) AS age,
    COUNT(DISTINCT s.session_id) AS total_sessions,
    SUM(CASE WHEN s.flight_booked THEN 1 ELSE 0 END) AS flights_booked,
    SUM(CASE WHEN s.flight_discount THEN 1 ELSE 0 END) AS flight_discounts_offered,
    SUM(CASE WHEN s.flight_booked AND s.flight_discount THEN 1 ELSE 0 END) AS flights_booked_with_discount,
    SUM(CASE WHEN s.flight_booked AND s.flight_discount = FALSE THEN 1 ELSE 0 END) AS flights_booked_without_discount,
    SUM(CASE WHEN f.return_flight_booked = TRUE THEN 1 ELSE 0 END) AS return_flights_booked,
    AVG(s.flight_discount_amount * f.base_fare_usd) AS ADS,
    AVG(s.flight_discount_amount * f.base_fare_usd) / NULLIF(SUM(k.sum_distance_in_km), 0) AS ADS_per_km,
    ROUND(AVG(f.seats), 0) AS avg_amount_people_travelling,
    SUM(CASE WHEN s.hotel_booked THEN 1 ELSE 0 END) AS hotels_booked,
    SUM(CASE WHEN s.hotel_discount THEN 1 ELSE 0 END) AS hotel_discounts_offered,
    SUM(CASE WHEN s.hotel_booked AND s.hotel_discount THEN 1 ELSE 0 END) AS hotels_booked_with_discount,
    SUM(CASE WHEN s.hotel_booked AND s.hotel_discount = FALSE THEN 1 ELSE 0 END) AS hotels_booked_without_discount,
    SUM(CASE WHEN s.cancellation THEN 1 ELSE 0 END) AS cancellations,
    SUM(CASE WHEN f.checked_bags > 0 THEN 1 ELSE 0 END) AS checked_bags,
    SUM(h.rooms) / NULLIF(SUM(CASE WHEN s.hotel_booked THEN 1 ELSE 0 END), 0) AS avg_rooms_booked_per_trip,
    SUM(h.nights) / NULLIF(SUM(CASE WHEN s.hotel_booked THEN 1 ELSE 0 END), 0) AS avg_nights_booked_per_trip,
    AVG(h.hotel_per_room_usd) AS avg_price_per_room,
    AVG(f.base_fare_usd) AS avg_price_per_flight,
    SUM(s.page_clicks) / COUNT(DISTINCT s.session_id) AS avg_clicks_per_session,
    (SUM(EXTRACT(EPOCH FROM (s.session_end - s.session_start))) / NULLIF(COUNT(DISTINCT s.session_id), 0)) AS avg_session_length,
    k.avg_distance_in_km AS avg_distance_travelled    
FROM
    users u
LEFT JOIN
    sessions s ON u.user_id = s.user_id
LEFT JOIN
    flights f ON s.trip_id = f.trip_id
LEFT JOIN
    hotels h ON s.trip_id = h.trip_id
LEFT JOIN
    kilometers k ON u.user_id = k.user_id
WHERE
    s.session_start >= '2023-01-04'::DATE
    AND (flight_discount_amount < 0.565 OR flight_discount_amount IS NULL)
GROUP BY
    u.user_id, u.gender, u.married, u.has_children, u.home_country, u.home_city, u.home_airport, k.avg_distance_in_km
HAVING
    COUNT(DISTINCT s.session_id) > 7
ORDER BY
    u.user_id;


