import { Injectable, OnModuleDestroy } from "@nestjs/common";
import { ConfigService } from "@nestjs/config";
import Redis from "ioredis";

@Injectable()
export class RedisService implements OnModuleDestroy {
  private readonly client: Redis;

  constructor(config: ConfigService) {
    this.client = new Redis(config.getOrThrow<string>("REDIS_URL"), {
      lazyConnect: true,
      connectTimeout: 3_000,
      commandTimeout: 3_000,
      maxRetriesPerRequest: 1,
    });
    this.client.on("error", () => undefined);
  }

  ping(): Promise<string> {
    return this.client.ping();
  }

  async getJson<T>(key: string): Promise<T | undefined> {
    const value = await this.client.get(key);
    if (!value) return undefined;
    return JSON.parse(value) as T;
  }

  async setJson(key: string, value: unknown, ttlSeconds: number) {
    await this.client.set(key, JSON.stringify(value), "EX", ttlSeconds);
  }

  async onModuleDestroy() {
    if (this.client.status === "ready") {
      try {
        await this.client.quit();
        return;
      } catch {
        this.client.disconnect(false);
        return;
      }
    }
    this.client.disconnect(false);
  }
}
