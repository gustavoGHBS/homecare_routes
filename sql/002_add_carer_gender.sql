ALTER TABLE carer
    ADD COLUMN gender gender_enum NOT NULL;

COMMENT ON COLUMN carer.gender IS 'Carer gender; used for client matching (male carers serve male clients only; female carers serve all)';


ALTER TABLE client ALTER COLUMN gender SET NOT NULL;

