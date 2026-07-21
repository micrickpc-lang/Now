import { Queue, Worker } from "bullmq";
import { Pool } from "pg";

const databaseUrl = process.env.DATABASE_URL;
const redisUrl = process.env.REDIS_URL;
if (!databaseUrl || !redisUrl)
  throw new Error("DATABASE_URL and REDIS_URL are required");

const redis = new URL(redisUrl);
const connection = {
  host: redis.hostname,
  port: Number(redis.port || 6379),
  username: redis.username || undefined,
  password: redis.password || undefined,
  db: Number(redis.pathname.slice(1) || 0),
  maxRetriesPerRequest: null,
};
const pool = new Pool({ connectionString: databaseUrl, max: 5 });
const queue = new Queue("maintenance", { connection });

async function sweep() {
  const client = await pool.connect();
  try {
    await client.query("BEGIN");
    const locations = await client.query(
      "DELETE FROM location_shares WHERE expires_at <= now() RETURNING id",
    );
    const signals = await client.query(`
      UPDATE signals SET state = 'EXPIRED', updated_at = now()
      WHERE expires_at <= now() AND state IN ('ACTIVE', 'FULL') RETURNING id
    `);
    const rooms = await client.query(`
      UPDATE temporary_rooms SET state = 'ARCHIVED', completed_at = COALESCE(completed_at, now())
      WHERE expires_at <= now() AND state = 'ACTIVE' RETURNING id
    `);
    await client.query(`
      DELETE FROM location_shares
      WHERE room_id IN (SELECT id FROM temporary_rooms WHERE state <> 'ACTIVE')
    `);
    await client.query(`
      DELETE FROM otp_challenges WHERE expires_at < now() - interval '24 hours'
    `);
    await client.query(`
      DELETE FROM auth_sessions WHERE expires_at < now() - interval '30 days'
    `);
    await client.query("COMMIT");
    process.stdout.write(
      JSON.stringify({
        level: "info",
        event: "ttl_sweep",
        expiredLocations: locations.rowCount,
        expiredSignals: signals.rowCount,
        archivedRooms: rooms.rowCount,
        time: new Date().toISOString(),
      }) + "\n",
    );
  } catch (error) {
    await client.query("ROLLBACK");
    throw error;
  } finally {
    client.release();
  }
}

const worker = new Worker(
  "maintenance",
  async (job) => {
    if (job.name === "ttl-sweep") await sweep();
  },
  { connection, concurrency: 2 },
);

worker.on("failed", (job, error) => {
  process.stderr.write(
    JSON.stringify({
      level: "error",
      event: "job_failed",
      jobId: job?.id,
      error: error.message,
    }) + "\n",
  );
});

async function shutdown() {
  await worker.close();
  await queue.close();
  await pool.end();
  process.exit(0);
}

process.once("SIGTERM", () => void shutdown());
process.once("SIGINT", () => void shutdown());

async function bootstrap() {
  await queue.add(
    "ttl-sweep",
    {},
    {
      repeat: { every: 60_000 },
      jobId: "ttl-sweep",
      removeOnComplete: 20,
      removeOnFail: 100,
    },
  );
}

void bootstrap();
