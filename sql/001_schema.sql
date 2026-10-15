-- ============================================================================
-- homecare_routes Database Schema
-- PostgreSQL + PostGIS
-- Generated: 2026-10-15
-- ============================================================================

-- Enable PostGIS extension
CREATE EXTENSION IF NOT EXISTS postgis;
CREATE EXTENSION IF NOT EXISTS postgis_topology;

-- ============================================================================
-- ENUM TYPES
-- ============================================================================

-- client gender
CREATE TYPE gender_enum AS ENUM (
    'male',
    'female',
    'other'
);

-- client marital status
CREATE TYPE marital_status_enum AS ENUM (
    'single',
    'married',
    'widowed',
    'divorced',
    'separated'
);

-- carer transport mode
CREATE TYPE transport_mode_enum AS ENUM (
    'car',
    'public_transport',
    'regular_bike',
    'electric_bike_scooter'
);

-- carer role / job title
CREATE TYPE carer_role_enum AS ENUM (
    'care',
    'supervisor',
    'rapid_responder'
);

-- route calculation mode
CREATE TYPE route_calc_mode_enum AS ENUM (
    'automatic',
    'manual'
);

-- route status
CREATE TYPE route_status_enum AS ENUM (
    'draft',
    'confirmed',
    'in_progress',
    'completed'
);

-- visit event type
CREATE TYPE visit_event_type_enum AS ENUM (
    'visit',
    'overnight',
    'time_freeze',
    'break'
);

-- visit status
CREATE TYPE visit_status_enum AS ENUM (
    'pending',
    'in_progress',
    'completed',
    'cancelled'
);

-- client contact relationship type
CREATE TYPE contact_relationship_enum AS ENUM (
    'next_of_kin',
    'emergency_contact',
    'other'
);

-- ============================================================================
-- TABLES
-- ============================================================================

-- ZONE: Geographic coverage areas (Irish local zones, e.g., D01, D02)
CREATE TABLE zone (
    id SERIAL PRIMARY KEY,
    name VARCHAR(255) NOT NULL,
    code VARCHAR(10) NOT NULL UNIQUE,
    geometry GEOMETRY(MULTIPOLYGON, 4326) NOT NULL,  -- PostGIS: Irish grid (EPSG:4326 WGS84)
    description TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- Create spatial index for zone.geometry (GIST for fast spatial queries)
CREATE INDEX idx_zone_geometry ON zone USING GIST (geometry);
COMMENT ON TABLE zone IS 'Geographic zones for service coverage (e.g., Dublin postcodes D01-D24)';
COMMENT ON COLUMN zone.geometry IS 'Polygon/MultiPolygon representing zone boundary; CRS EPSG:4326 (WGS84)';

-- ============================================================================

-- CLIENT: Patients receiving home care services
CREATE TABLE client (
    id SERIAL PRIMARY KEY,
    client_no INTEGER NOT NULL UNIQUE,  -- Client reference number (e.g., 10100)
    full_name VARCHAR(255) NOT NULL,
    nickname VARCHAR(100),
    dob DATE,
    gender gender_enum,
    marital_status marital_status_enum,
    address_line1 VARCHAR(255),
    address_line2 VARCHAR(255),
    locality VARCHAR(100),  -- e.g., Templeogue
    post_code VARCHAR(10) NOT NULL,  -- EIRCODE (e.g., D12 A1B2)
    phone VARCHAR(20),
    access_directions TEXT,  -- Special instructions for home access
    location GEOGRAPHY(POINT, 4326),  -- PostGIS: Client home coordinates (WGS84)
    zone_id INTEGER NOT NULL REFERENCES zone(id) ON DELETE RESTRICT,
    active BOOLEAN NOT NULL DEFAULT TRUE,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- Create spatial index for client.location (GIST for fast proximity queries)
CREATE INDEX idx_client_location ON client USING GIST (location);
CREATE INDEX idx_client_zone ON client (zone_id);
CREATE INDEX idx_client_active ON client (active);
COMMENT ON TABLE client IS 'Patients/service users receiving home care visits';
COMMENT ON COLUMN client.location IS 'Home location as POINT; CRS EPSG:4326 (WGS84)';
COMMENT ON COLUMN client.post_code IS 'Irish EIRCODE (Eircode format): 6 alphanumeric chars';

-- ============================================================================

-- CLIENT_CONTACT: Emergency contacts / Next of Kin for clients
CREATE TABLE client_contact (
    id SERIAL PRIMARY KEY,
    client_id INTEGER NOT NULL REFERENCES client(id) ON DELETE CASCADE,
    full_name VARCHAR(255) NOT NULL,
    phone VARCHAR(20) NOT NULL,
    relationship contact_relationship_enum NOT NULL,
    is_primary BOOLEAN NOT NULL DEFAULT FALSE,  -- Primary contact first to call
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_client_contact_client ON client_contact (client_id);
COMMENT ON TABLE client_contact IS 'Emergency contacts and next of kin for each client';
COMMENT ON COLUMN client_contact.is_primary IS 'TRUE = primary/first contact to call in emergencies';

-- ============================================================================

-- CARER: Healthcare professionals delivering services
CREATE TABLE carer (
    id SERIAL PRIMARY KEY,
    code VARCHAR(20) NOT NULL UNIQUE,  -- Employee ID (e.g., CRR001)
    full_name VARCHAR(255) NOT NULL,
    address_line1 VARCHAR(255),
    address_line2 VARCHAR(255),
    post_code VARCHAR(10),
    nationality VARCHAR(100),
    transport_mode transport_mode_enum NOT NULL,  -- Preferred transport method
    role carer_role_enum NOT NULL,  -- Job role (care, supervisor, rapid_responder)
    zone_id INTEGER NOT NULL REFERENCES zone(id) ON DELETE RESTRICT,  -- Base zone
    active BOOLEAN NOT NULL DEFAULT TRUE,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_carer_zone ON carer (zone_id);
CREATE INDEX idx_carer_active ON carer (active);
CREATE INDEX idx_carer_code ON carer (code);
COMMENT ON TABLE carer IS 'Healthcare professionals (care workers, supervisors, rapid responders)';
COMMENT ON COLUMN carer.transport_mode IS 'Primary mode of transport for visiting clients';
COMMENT ON COLUMN carer.zone_id IS 'Home/base zone for assignment and dispatch';

-- ============================================================================

-- SERVICE_TYPE: Types of services offered
CREATE TABLE service_type (
    id SERIAL PRIMARY KEY,
    name VARCHAR(255) NOT NULL UNIQUE,
    description TEXT,
    default_duration_min INTEGER,  -- Typical visit duration in minutes
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

COMMENT ON TABLE service_type IS 'Catalog of home care service types (e.g., bathing, medication, physiotherapy)';
COMMENT ON COLUMN service_type.default_duration_min IS 'Standard visit duration; can be overridden per visit';

-- ============================================================================

-- ROUTE: Daily route for a carer
CREATE TABLE route (
    id SERIAL PRIMARY KEY,
    carer_id INTEGER NOT NULL REFERENCES carer(id) ON DELETE CASCADE,
    route_date DATE NOT NULL,  -- Date of the route
    calc_mode route_calc_mode_enum NOT NULL,  -- automatic or manual calculation
    total_distance_km NUMERIC(10, 2),  -- Total route distance
    estimated_duration_min INTEGER,  -- Total estimated time for the route
    status route_status_enum NOT NULL DEFAULT 'draft',
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_route_carer ON route (carer_id);
CREATE INDEX idx_route_date ON route (route_date);
CREATE INDEX idx_route_status ON route (status);
COMMENT ON TABLE route IS 'Daily route plan for a single carer';
COMMENT ON COLUMN route.calc_mode IS 'automatic = system-optimized order; manual = user-defined order (shows distance)';

-- ============================================================================

-- VISIT: Individual visit within a route
CREATE TABLE visit (
    id SERIAL PRIMARY KEY,
    route_id INTEGER NOT NULL REFERENCES route(id) ON DELETE CASCADE,
    client_id INTEGER NOT NULL REFERENCES client(id) ON DELETE RESTRICT,
    service_type_id INTEGER REFERENCES service_type(id) ON DELETE SET NULL,
    sequence INTEGER NOT NULL,  -- Order in the route (1, 2, 3, ...)
    event_type visit_event_type_enum NOT NULL,  -- visit, overnight, time_freeze, break
    scheduled_start TIMESTAMPTZ,  -- Planned start time
    scheduled_end TIMESTAMPTZ,  -- Planned end time
    estimated_duration_min INTEGER,  -- Estimated duration of this visit
    distance_to_next_km NUMERIC(10, 2),  -- Distance to the next visit (manual mode info)
    status visit_status_enum NOT NULL DEFAULT 'pending',
    notes TEXT,  -- Special instructions or observations
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_visit_route ON visit (route_id);
CREATE INDEX idx_visit_client ON visit (client_id);
CREATE INDEX idx_visit_status ON visit (status);
CREATE INDEX idx_visit_scheduled_start ON visit (scheduled_start);
COMMENT ON TABLE visit IS 'Individual visit/appointment within a route';
COMMENT ON COLUMN visit.event_type IS 'visit=normal visit, overnight=overnight stay, time_freeze=blocked time, break=carer break';
COMMENT ON COLUMN visit.distance_to_next_km IS 'Distance to next visit in route; used in manual mode for display';

-- ============================================================================
-- CONSTRAINTS & CHECKS
-- ============================================================================

ALTER TABLE visit ADD CONSTRAINT visit_scheduled_order
    CHECK (scheduled_start < scheduled_end);

ALTER TABLE route ADD CONSTRAINT route_distance_positive
    CHECK (total_distance_km >= 0);

ALTER TABLE visit ADD CONSTRAINT visit_distance_positive
    CHECK (distance_to_next_km >= 0);

ALTER TABLE service_type ADD CONSTRAINT service_type_duration_positive
    CHECK (default_duration_min > 0);

-- ============================================================================
-- SAMPLE DATA (OPTIONAL - for testing)
-- ============================================================================

-- Insert sample zone (Dublin D01)
-- INSERT INTO zone (name, code, geometry, description) VALUES
-- (
--     'Dublin City Centre',
--     'D01',
--     ST_GeomFromText('MULTIPOLYGON(((-6.2714 53.3428, -6.2500 53.3428, -6.2500 53.3600, -6.2714 53.3600, -6.2714 53.3428)))', 4326),
--     'Dublin city centre postal zone'
-- );

-- ============================================================================
-- END OF SCHEMA
-- ============================================================================
