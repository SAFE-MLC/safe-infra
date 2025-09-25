\c safe;

CREATE TABLE events (id TEXT PRIMARY KEY, name TEXT NOT NULL,
  start_at TIMESTAMPTZ NOT NULL, end_at TIMESTAMPTZ NOT NULL,
  status TEXT NOT NULL DEFAULT 'SCHEDULED');

CREATE TABLE gates (id TEXT PRIMARY KEY, event_id TEXT REFERENCES events(id) NOT NULL, name TEXT NOT NULL);
CREATE TABLE zones (id TEXT PRIMARY KEY, event_id TEXT REFERENCES events(id) NOT NULL, name TEXT NOT NULL);
CREATE TABLE zone_checkpoints (id TEXT PRIMARY KEY, zone_id TEXT REFERENCES zones(id) NOT NULL, name TEXT NOT NULL);

CREATE TABLE tickets (
  id TEXT PRIMARY KEY, event_id TEXT REFERENCES events(id) NOT NULL,
  holder TEXT, status TEXT NOT NULL CHECK (status IN ('ACTIVE','USED','REVOKED')),
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(), used_at TIMESTAMPTZ
);
CREATE INDEX idx_tickets_event ON tickets(event_id);
CREATE INDEX idx_tickets_status ON tickets(status);

CREATE TABLE zone_entitlements (
  ticket_id TEXT REFERENCES tickets(id) NOT NULL,
  zone_id TEXT REFERENCES zones(id) NOT NULL,
  PRIMARY KEY(ticket_id, zone_id)
);

CREATE TABLE staff (
  id TEXT PRIMARY KEY, display_name TEXT NOT NULL,
  role TEXT NOT NULL CHECK (role IN ('GATE','ZONE')),
  pin_hash TEXT NOT NULL, gate_id TEXT REFERENCES gates(id),
  zone_checkpoint_id TEXT REFERENCES zone_checkpoints(id)
);

CREATE TABLE ticket_scans (
  id BIGSERIAL PRIMARY KEY, ticket_id TEXT REFERENCES tickets(id) NOT NULL,
  kind TEXT NOT NULL CHECK (kind IN ('GATE','ZONE')),
  gate_id TEXT REFERENCES gates(id), zone_checkpoint_id TEXT REFERENCES zone_checkpoints(id),
  ts TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
CREATE INDEX idx_ticket_scans_ticket ON ticket_scans(ticket_id);

CREATE TABLE zone_presence (
  id BIGSERIAL PRIMARY KEY, ticket_id TEXT REFERENCES tickets(id) NOT NULL,
  zone_id TEXT REFERENCES zones(id) NOT NULL,
  checkpoint_id TEXT REFERENCES zone_checkpoints(id) NOT NULL,
  direction TEXT NOT NULL CHECK (direction IN ('IN')),
  ts TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
CREATE INDEX idx_zone_presence_zone ON zone_presence(zone_id);

-- Funciones idempotentes
CREATE OR REPLACE FUNCTION consume_ticket(p_ticket_id TEXT, p_gate_id TEXT)
RETURNS BOOLEAN LANGUAGE plpgsql AS $$
DECLARE v_rows INT;
BEGIN
  UPDATE tickets SET status='USED', used_at=NOW()
   WHERE id=p_ticket_id AND status='ACTIVE';
  GET DIAGNOSTICS v_rows = ROW_COUNT;

  INSERT INTO ticket_scans(ticket_id, kind, gate_id, ts)
  VALUES (p_ticket_id, 'GATE', p_gate_id, NOW());

  RETURN v_rows = 1;
END $$;

CREATE OR REPLACE FUNCTION zone_enter(p_ticket_id TEXT, p_zone_id TEXT, p_checkpoint_id TEXT)
RETURNS VOID LANGUAGE sql AS $$
  INSERT INTO zone_presence(ticket_id, zone_id, checkpoint_id, direction, ts)
  VALUES (p_ticket_id, p_zone_id, p_checkpoint_id, 'IN', NOW());
$$;

-- Roles mínimos (un schema público sencillo para el MVP)
CREATE ROLE gate_ms LOGIN PASSWORD 'gate_pw';
GRANT USAGE ON SCHEMA public TO gate_ms;
GRANT SELECT ON tickets, zone_entitlements TO gate_ms;
GRANT SELECT ON zones, zone_checkpoints, gates TO gate_ms;
GRANT UPDATE ON tickets TO gate_ms;
GRANT INSERT ON ticket_scans TO gate_ms;
GRANT EXECUTE ON FUNCTION consume_ticket(TEXT, TEXT) TO gate_ms;

CREATE ROLE zone_ms LOGIN PASSWORD 'zone_pw';
GRANT USAGE ON SCHEMA public TO zone_ms;
GRANT SELECT ON tickets, zone_entitlements, zones, zone_checkpoints TO zone_ms;
GRANT INSERT ON zone_presence TO zone_ms;
GRANT INSERT ON ticket_scans TO zone_ms;
GRANT EXECUTE ON FUNCTION zone_enter(TEXT, TEXT, TEXT) TO zone_ms;
