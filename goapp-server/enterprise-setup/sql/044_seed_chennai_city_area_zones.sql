BEGIN;

-- Seed a complete Chennai service coverage set as ALLOWED zones.
-- Idempotent insert: keyed by (name, applies_to, is_allowed) in NOT EXISTS checks.
-- Geo filters use country/state + representative locality pincode.

INSERT INTO zone_restrictions (
  name, lat, lng, radius_km, applies_to, is_allowed,
  country, state, pincode, is_enabled, restriction_message, created_by
)
SELECT
  v.name, v.lat, v.lng, v.radius_km, 'both', true,
  'IN', 'TAMIL NADU', v.pincode, true,
  'Service is not available in your area yet.',
  'system_seed_044'
FROM (
  VALUES
    ('Chennai - Central',        13.0827::DECIMAL(10,7), 80.2707::DECIMAL(10,7), 6.0::DECIMAL(8,3), '600003'),
    ('Chennai - T Nagar',        13.0418::DECIMAL(10,7), 80.2341::DECIMAL(10,7), 5.0::DECIMAL(8,3), '600017'),
    ('Chennai - Mylapore',       13.0339::DECIMAL(10,7), 80.2619::DECIMAL(10,7), 4.0::DECIMAL(8,3), '600004'),
    ('Chennai - Egmore',         13.0732::DECIMAL(10,7), 80.2609::DECIMAL(10,7), 4.0::DECIMAL(8,3), '600008'),
    ('Chennai - Marina',         13.0500::DECIMAL(10,7), 80.2824::DECIMAL(10,7), 4.0::DECIMAL(8,3), '600005'),
    ('Chennai - Guindy',         13.0067::DECIMAL(10,7), 80.2206::DECIMAL(10,7), 5.0::DECIMAL(8,3), '600032'),
    ('Chennai - Adyar',          13.0012::DECIMAL(10,7), 80.2565::DECIMAL(10,7), 5.0::DECIMAL(8,3), '600020'),
    ('Chennai - Velachery',      12.9755::DECIMAL(10,7), 80.2211::DECIMAL(10,7), 5.0::DECIMAL(8,3), '600042'),
    ('Chennai - OMR Corridor',   12.9350::DECIMAL(10,7), 80.2300::DECIMAL(10,7), 9.0::DECIMAL(8,3), '600097'),
    ('Chennai - Sholinganallur', 12.9010::DECIMAL(10,7), 80.2279::DECIMAL(10,7), 5.5::DECIMAL(8,3), '600097'),
    ('Chennai - Perungudi',      12.9629::DECIMAL(10,7), 80.2411::DECIMAL(10,7), 4.0::DECIMAL(8,3), '600096'),
    ('Chennai - Thoraipakkam',   12.9488::DECIMAL(10,7), 80.2414::DECIMAL(10,7), 4.0::DECIMAL(8,3), '600097'),
    ('Chennai - Airport',        12.9941::DECIMAL(10,7), 80.1709::DECIMAL(10,7), 6.5::DECIMAL(8,3), '600016'),
    ('Chennai - Tambaram',       12.9249::DECIMAL(10,7), 80.1000::DECIMAL(10,7), 7.5::DECIMAL(8,3), '600045'),
    ('Chennai - Anna Nagar',     13.0850::DECIMAL(10,7), 80.2101::DECIMAL(10,7), 6.0::DECIMAL(8,3), '600040'),
    ('Chennai - Porur',          13.0381::DECIMAL(10,7), 80.1565::DECIMAL(10,7), 5.0::DECIMAL(8,3), '600116'),
    ('Chennai - Ambattur',       13.1143::DECIMAL(10,7), 80.1548::DECIMAL(10,7), 6.0::DECIMAL(8,3), '600053')
) AS v(name, lat, lng, radius_km, pincode)
WHERE NOT EXISTS (
  SELECT 1
  FROM zone_restrictions z
  WHERE z.name = v.name
    AND z.applies_to = 'both'
    AND z.is_allowed = true
);

COMMIT;
