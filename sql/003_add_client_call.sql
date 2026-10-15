-- ====
-- 003_add_client_call.sql
-- Planned daily calls per client (needs). Applies every day.
-- A client has 1 to 4 calls per day; the carer is only assigned later, in visit.
-- ====

CREATE TABLE client_call (
    id SERIAL PRIMARY KEY,
    client_id INTEGER NOT NULL REFERENCES client(id) ON DELETE CASCADE,
    service_type_id INTEGER REFERENCES service_type(id) ON DELETE SET NULL,
    call_order SMALLINT NOT NULL,
    preferred_start_time TIME NOT NULL,
    duration_min INTEGER NOT NULL,
    is_overnight BOOLEAN NOT NULL DEFAULT FALSE,
    active BOOLEAN NOT NULL DEFAULT TRUE,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    CONSTRAINT client_call_order_range CHECK (call_order BETWEEN 1 AND 4),
    CONSTRAINT client_call_duration_range CHECK (duration_min BETWEEN 30 AND 720),
    CONSTRAINT client_call_unique_order UNIQUE (client_id, call_order)
);

CREATE INDEX idx_client_call_client ON client_call (client_id);
COMMENT ON TABLE client_call IS 'Planned daily call of a client (1-4 per day, every day); carer assigned later in visit';
COMMENT ON COLUMN client_call.duration_min IS 'Editable duration in minutes: min 30, max 720 (overnight 8 p.m. - 8 a.m.)';
COMMENT ON COLUMN client_call.is_overnight IS 'TRUE = overnight stay, 20:00 to 08:00';

ALTER TABLE visit
    ADD COLUMN client_call_id INTEGER
    REFERENCES client_call(id) ON DELETE SET NULL;

CREATE INDEX idx_visit_client_call ON visit (client_call_id);