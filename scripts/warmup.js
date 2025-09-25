// Warm-up: FLUSHDB (opcional) + cargar tickets/checkpoints desde Postgres a Redis
const { Client } = require('pg');
const Redis = require('ioredis');

const EVENT_ID = process.env.EVENT_ID || 'evt_1';
const DO_FLUSH = (process.env.WARMUP_FLUSH_REDIS || 'true').toLowerCase() === 'true'; // por defecto: true

const PG = new Client({
  host: process.env.PGHOST || 'localhost',
  user: process.env.PGUSER || 'postgres',
  password: process.env.PGPASSWORD || 'postgres_pw',
  database: process.env.PGDATABASE || 'safe',
  port: process.env.PGPORT ? Number(process.env.PGPORT) : 5432
});
const redis = new Redis(process.env.REDIS_URL || 'redis://localhost:6379');

(async () => {
  await PG.connect();

  // 1) (Opcional) resetear Redis completo
  if (DO_FLUSH) {
    const info = await redis.info('server');
    console.log(`Redis INFO: ${info.split('\n')[1] || ''}`.trim());
    console.log('FLUSHDB: limpiando Redis…');
    await redis.flushdb();
  } else {
    console.log('WARMUP_FLUSH_REDIS=false → no se hace FLUSHDB');
  }

  // 2) Tickets + entitlements (SETEX, TTL 120s)
  const qTickets = `
    SELECT t.id AS ticket_id, t.status, t.event_id,
           COALESCE(ARRAY_AGG(ze.zone_id) FILTER (WHERE ze.zone_id IS NOT NULL), '{}') AS entitlements
    FROM tickets t
    LEFT JOIN zone_entitlements ze ON ze.ticket_id = t.id
    WHERE t.event_id = $1
    GROUP BY t.id, t.status, t.event_id
  `;
  const { rows: tickets } = await PG.query(qTickets, [EVENT_ID]);
  for (const r of tickets) {
    await redis.setex(`ticket:${r.ticket_id}`, 3600, JSON.stringify({
      status: r.status,
      entitlements: r.entitlements || [],
      eventId: r.event_id
    }));
  }

  // 3) Checkpoints (SET sin TTL; config cache “largo”)
  const qCps = `
    SELECT zc.id AS zone_checkpoint_id, z.id AS zone_id, z.name AS zone_name, z.event_id
    FROM zone_checkpoints zc JOIN zones z ON zc.zone_id = z.id
    WHERE z.event_id = $1
  `;
  const { rows: cps } = await PG.query(qCps, [EVENT_ID]);
  for (const c of cps) {
    await redis.set(`checkpoint:${c.zone_checkpoint_id}`, JSON.stringify({
      zoneId: c.zone_id,
      zoneName: c.zone_name,
      eventId: c.event_id
    }));
  }

  // 4) (Opcional) limpiar logs calientes
  await redis.del(`scanlog:gate:${EVENT_ID}`);
  await redis.del(`scanlog:zone:${EVENT_ID}`);

  console.log(`Warmup OK (flush=${DO_FLUSH}) — tickets=${tickets.length}, checkpoints=${cps.length}`);
  await PG.end(); await redis.quit();
})().catch(err => { console.error(err); process.exit(1); });
