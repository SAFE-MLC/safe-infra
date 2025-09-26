\c safe;

-- =============================
-- Tablas
-- =============================
CREATE TABLE IF NOT EXISTS events (
  id TEXT PRIMARY KEY,
  name TEXT NOT NULL,
  start_at TIMESTAMPTZ NOT NULL,
  end_at TIMESTAMPTZ NOT NULL,
  status TEXT NOT NULL DEFAULT 'SCHEDULED'
);

CREATE TABLE IF NOT EXISTS gates (
  id TEXT PRIMARY KEY,
  event_id TEXT REFERENCES events(id) NOT NULL,
  name TEXT NOT NULL
);

CREATE TABLE IF NOT EXISTS zones (
  id TEXT PRIMARY KEY,
  event_id TEXT REFERENCES events(id) NOT NULL,
  name TEXT NOT NULL
);

CREATE TABLE IF NOT EXISTS zone_checkpoints (
  id TEXT PRIMARY KEY,
  zone_id TEXT REFERENCES zones(id) NOT NULL,
  name TEXT NOT NULL
);

CREATE TABLE IF NOT EXISTS tickets (
  id TEXT PRIMARY KEY,
  event_id TEXT REFERENCES events(id) NOT NULL,
  holder TEXT,
  status TEXT NOT NULL CHECK (status IN ('ACTIVE','USED','REVOKED')),
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  used_at TIMESTAMPTZ
);
CREATE INDEX IF NOT EXISTS idx_tickets_event ON tickets(event_id);
CREATE INDEX IF NOT EXISTS idx_tickets_status ON tickets(status);

CREATE TABLE IF NOT EXISTS zone_entitlements (
  ticket_id TEXT REFERENCES tickets(id) NOT NULL,
  zone_id TEXT REFERENCES zones(id) NOT NULL,
  PRIMARY KEY(ticket_id, zone_id)
);

CREATE TABLE IF NOT EXISTS staff (
  id TEXT PRIMARY KEY,
  display_name TEXT NOT NULL,
  role TEXT NOT NULL CHECK (role IN ('GATE','ZONE')),
  pin_hash TEXT NOT NULL,
  gate_id TEXT REFERENCES gates(id),
  zone_checkpoint_id TEXT REFERENCES zone_checkpoints(id)
);

CREATE TABLE IF NOT EXISTS ticket_scans (
  id BIGSERIAL PRIMARY KEY,
  ticket_id TEXT REFERENCES tickets(id) NOT NULL,
  kind TEXT NOT NULL CHECK (kind IN ('GATE','ZONE')),
  gate_id TEXT REFERENCES gates(id),
  zone_checkpoint_id TEXT REFERENCES zone_checkpoints(id),
  ts TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
CREATE INDEX IF NOT EXISTS idx_ticket_scans_ticket ON ticket_scans(ticket_id);

CREATE TABLE IF NOT EXISTS zone_presence (
  id BIGSERIAL PRIMARY KEY,
  ticket_id TEXT REFERENCES tickets(id) NOT NULL,
  zone_id TEXT REFERENCES zones(id) NOT NULL,
  checkpoint_id TEXT REFERENCES zone_checkpoints(id) NOT NULL,
  direction TEXT NOT NULL CHECK (direction IN ('IN')),
  ts TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
CREATE INDEX IF NOT EXISTS idx_zone_presence_zone ON zone_presence(zone_id);

-- =============================
-- Funciones
-- =============================
CREATE OR REPLACE FUNCTION consume_ticket(p_ticket_id TEXT, p_gate_id TEXT)
RETURNS BOOLEAN LANGUAGE plpgsql AS $$
DECLARE
  v_rows INT;
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

-- Asegurar owner y SECURITY DEFINER + search_path fijo
ALTER FUNCTION consume_ticket(TEXT, TEXT) OWNER TO postgres;
ALTER FUNCTION zone_enter(TEXT, TEXT, TEXT) OWNER TO postgres;
ALTER FUNCTION consume_ticket(TEXT, TEXT) SECURITY DEFINER;
ALTER FUNCTION zone_enter(TEXT, TEXT, TEXT) SECURITY DEFINER;
ALTER FUNCTION consume_ticket(TEXT, TEXT) SET search_path = public;
ALTER FUNCTION zone_enter(TEXT, TEXT, TEXT) SET search_path = public;

-- =============================
-- Roles (idempotente)
-- =============================
DO $$
BEGIN
  IF NOT EXISTS (SELECT FROM pg_roles WHERE rolname = 'gate_ms') THEN
    CREATE ROLE gate_ms LOGIN PASSWORD 'gate_pw';
  END IF;
  IF NOT EXISTS (SELECT FROM pg_roles WHERE rolname = 'zone_ms') THEN
    CREATE ROLE zone_ms LOGIN PASSWORD 'zone_pw';
  END IF;
END $$;

-- =============================
-- Permisos en esquema/tablas/funciones
-- =============================
GRANT USAGE ON SCHEMA public TO gate_ms, zone_ms;

-- Gate MS: lee/consume tickets y registra escaneos
GRANT SELECT, UPDATE ON TABLE tickets TO gate_ms;
GRANT INSERT ON TABLE ticket_scans TO gate_ms;
GRANT SELECT ON TABLE zones, zone_checkpoints, gates, zone_entitlements, events TO gate_ms;
GRANT EXECUTE ON FUNCTION consume_ticket(TEXT, TEXT) TO gate_ms;

-- Zone MS: valida derecho de zona y registra presencia
-- (🔧 FIX principal) dar SELECT sobre tickets
GRANT SELECT ON TABLE tickets TO zone_ms;
GRANT SELECT ON TABLE zones, zone_checkpoints, gates TO zone_ms;
GRANT SELECT ON TABLE zone_entitlements TO zone_ms;
GRANT SELECT ON TABLE events TO zone_ms;
GRANT INSERT ON TABLE zone_presence TO zone_ms;
GRANT EXECUTE ON FUNCTION zone_enter(TEXT, TEXT, TEXT) TO zone_ms;

-- Secuencias necesarias para inserts (ticket_scans, zone_presence)
GRANT USAGE, SELECT ON ALL SEQUENCES IN SCHEMA public TO gate_ms, zone_ms;

-- Defaults futuros
ALTER DEFAULT PRIVILEGES IN SCHEMA public
  GRANT USAGE, SELECT ON SEQUENCES TO gate_ms, zone_ms;
