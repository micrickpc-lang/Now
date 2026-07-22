import {
  Inject,
  Injectable,
  ServiceUnavailableException,
} from "@nestjs/common";
import type { OnModuleDestroy } from "@nestjs/common";
import { ConfigService } from "@nestjs/config";
import Redis from "ioredis";

export const TYPING_STORE = Symbol("TYPING_STORE");
export const TYPING_TTL_SECONDS = 8;

export interface TypingStore {
  set(conversationId: string, userId: string): Promise<Date>;
  delete(conversationId: string, userId: string): Promise<void>;
}

@Injectable()
export class RedisTypingStore implements TypingStore, OnModuleDestroy {
  private readonly redis: Redis;

  constructor(config: ConfigService) {
    this.redis = new Redis(config.getOrThrow<string>("REDIS_URL"), {
      lazyConnect: true,
      enableOfflineQueue: false,
      maxRetriesPerRequest: 1,
      connectTimeout: 3_000,
    });
    this.redis.on("error", () => undefined);
  }

  async set(conversationId: string, userId: string): Promise<Date> {
    const expiresAt = new Date(Date.now() + TYPING_TTL_SECONDS * 1000);
    try {
      await this.ensureConnected();
      await this.redis.set(
        this.key(conversationId, userId),
        expiresAt.toISOString(),
        "EX",
        TYPING_TTL_SECONDS,
      );
      return expiresAt;
    } catch {
      throw new ServiceUnavailableException(
        "Typing state is temporarily unavailable",
      );
    }
  }

  async delete(conversationId: string, userId: string): Promise<void> {
    try {
      await this.ensureConnected();
      await this.redis.del(this.key(conversationId, userId));
    } catch {
      throw new ServiceUnavailableException(
        "Typing state is temporarily unavailable",
      );
    }
  }

  async onModuleDestroy(): Promise<void> {
    if (this.redis.status === "end") return;

    // Calling quit() while a lazy client is still waiting for its first
    // connection makes ioredis start connecting before rejecting the command.
    // That reconnect loop keeps short-lived workers (including Jest) alive.
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

  private async ensureConnected(): Promise<void> {
    if (this.redis.status === "wait") await this.redis.connect();
  }

  private key(conversationId: string, userId: string) {
    return `typing:${conversationId}:${userId}`;
  }
}

@Injectable()
export class InMemoryTypingStore implements TypingStore {
  private readonly entries = new Map<string, ReturnType<typeof setTimeout>>();

  set(conversationId: string, userId: string): Promise<Date> {
    const key = `${conversationId}:${userId}`;
    const existing = this.entries.get(key);
    if (existing) clearTimeout(existing);
    const expiresAt = new Date(Date.now() + TYPING_TTL_SECONDS * 1000);
    const timer = setTimeout(
      () => this.entries.delete(key),
      TYPING_TTL_SECONDS * 1000,
    );
    timer.unref();
    this.entries.set(key, timer);
    return Promise.resolve(expiresAt);
  }

  delete(conversationId: string, userId: string): Promise<void> {
    const key = `${conversationId}:${userId}`;
    const timer = this.entries.get(key);
    if (timer) clearTimeout(timer);
    this.entries.delete(key);
    return Promise.resolve();
  }
}

@Injectable()
export class TypingStateService {
  constructor(@Inject(TYPING_STORE) private readonly store: TypingStore) {}

  set(conversationId: string, userId: string) {
    return this.store.set(conversationId, userId);
  }

  delete(conversationId: string, userId: string) {
    return this.store.delete(conversationId, userId);
  }
}
