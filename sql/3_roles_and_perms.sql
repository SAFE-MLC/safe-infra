-- 03_roles_and_perms.sql
-- Ejecutar DESPUÉS de 01_schema_min.sql y 02_seed_min.sql

-- 1) Roles de microservicios (idempotente)
DO $$
BEGIN
  IF NOT EXISTS (SELECT FROM pg_roles WHERE rolname = 'gate_ms') THEN
    CREATE ROLE gate_ms LOGIN PASSWORD 'gate_pw';
  END IF;
  IF NOT EXISTS (SELECT FROM pg_roles WHERE rolname = 'zone_ms') THEN
    CREATE ROLE zone_ms LOGIN PASSWORD 'zone_pw';
  END IF;
END $$;

-- 2) Permisos básicos de esquema
GRANT USAGE ON SCHEMA public TO gate_ms, zone_ms;

-- 3) Permisos en tablas existentes
GRANT SELECT, UPDATE ON TABLE tickets TO gate_ms;
GRANT SELECT ON TABLE zone_entitlements TO gate_ms, zone_ms;
GRANT SELECT ON TABLE zones, zone_checkpoints, gates TO gate_ms, zone_ms;
GRANT INSERT ON TABLE ticket_scans TO gate_ms;
GRANT INSERT ON TABLE zone_presence TO zone_ms;

-- 4) Permisos en SECUENCIAS (⚠️ esto arregla tu error "permission denied for sequence ticket_scans_id_seq")
GRANT USAGE, SELECT ON ALL SEQUENCES IN SCHEMA public TO gate_ms, zone_ms;

-- 5) Default privileges a futuro (toda secuencia nueva hereda permisos)
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT USAGE, SELECT ON SEQUENCES TO gate_ms, zone_ms;

-- 6) Permisos sobre funciones
GRANT EXECUTE ON FUNCTION consume_ticket(TEXT, TEXT) TO gate_ms;
GRANT EXECUTE ON FUNCTION zone_enter(TEXT, TEXT, TEXT) TO zone_ms;

-- 7) (Opcional recomendado) Ejecutar funciones con permisos del dueño (evita problemas de GRANT finos)
-- Asegúrate de que postgres sea owner
ALTER FUNCTION consume_ticket(TEXT, TEXT) OWNER TO postgres;
ALTER FUNCTION zone_enter(TEXT, TEXT, TEXT) OWNER TO postgres;

-- SECURITY DEFINER y search_path seguro
ALTER FUNCTION consume_ticket(TEXT, TEXT) SECURITY DEFINER;
ALTER FUNCTION zone_enter(TEXT, TEXT, TEXT) SECURITY DEFINER;

-- Fija search_path dentro de la sesión de estas funciones (evita ataques por search_path)
COMMENT ON FUNCTION consume_ticket(TEXT, TEXT) IS 'search_path=public';
COMMENT ON FUNCTION zone_enter(TEXT, TEXT, TEXT) IS 'search_path=public';
