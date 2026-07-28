import { Injectable, ServiceUnavailableException } from "@nestjs/common";
import type { OnModuleDestroy } from "@nestjs/common";
import { ConfigService } from "@nestjs/config";
import Redis from "ioredis";

@Injectable()
export class RedisService implements OnModuleDestroy {
  private readonly redis: Redis;
  private connectPromise?: Promise<void>;

  constructor(config: ConfigService) {
    this.redis = new Redis(config.getOrThrow<string>("REDIS_URL"), {
      lazyConnect: true,
      enableOfflineQueue: false,
      maxRetriesPerRequest: 1,
      connectTimeout: 3_000,
    });
    this.redis.on("error", () => undefined);
  }

  async ping(): Promise<void> {
    try {
      await this.ensureConnected();
      await this.redis.ping();
    } catch {
      throw new ServiceUnavailableException("Redis is unavailable");
    }
  }

  async take(key: string, limit: number, ttlSeconds: number): Promise<boolean> {
    try {
      await this.ensureConnected();
      const count = await this.redis.eval(
        "local count = redis.call('INCR', KEYS[1]); if count == 1 then redis.call('EXPIRE', KEYS[1], ARGV[1]); end; return count",
        1,
        key,
        ttlSeconds,
      );
      return Number(count) <= limit;
    } catch {
      throw new ServiceUnavailableException(
        "Rate limiting is temporarily unavailable",
      );
    }
  }

  async onModuleDestroy(): Promise<void> {
    if (this.redis.status === "end") return;
    if (this.redis.status !== "ready") {
      this.redis.disconnect(false);
      return;
    }
    try {
      await this.redis.quit();
    } catch {
      this.redis.disconnect(false);
    }
  }

  private async ensureConnected() {
    if (this.redis.status === "ready") return;
    if (!this.connectPromise) {
      this.connectPromise = this.redis.connect().finally(() => {
        this.connectPromise = undefined;
      });
    }
    await this.connectPromise;
  }
}
