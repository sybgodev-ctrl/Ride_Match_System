-- 049_zone_restrictions_apply_both.sql
-- Force all existing zone restrictions to apply to both rider and driver.

UPDATE zone_restrictions
SET applies_to = 'both',
    updated_at = NOW()
WHERE applies_to IS DISTINCT FROM 'both';

