import type { ConfigService } from "@nestjs/config";
import Redis from "ioredis";
import {
  InMemoryTypingStore,
  RedisTypingStore,
  TYPING_TTL_SECONDS,
} from "./typing.store";

jest.mock("ioredis", () => ({
  __esModule: true,
  default: jest.fn().mockImplementation(() => ({
    status: "wait",
    on: jest.fn(),
    set: jest.fn(),
    del: jest.fn(),
    connect: jest.fn(),
    quit: jest.fn(),
    disconnect: jest.fn(),
  })),
}));

const redisMock = Redis as unknown as jest.Mock;

function createRedisStore() {
  const config = {
    getOrThrow: jest.fn().mockReturnValue("redis://localhost:6379/0"),
  } as unknown as ConfigService;
  const store = new RedisTypingStore(config);
  const client = redisMock.mock.results.at(-1)?.value as {
    status: string;
    quit: jest.Mock;
    disconnect: jest.Mock;
  };
  return { store, client };
}

describe("InMemoryTypingStore", () => {
  beforeEach(() => jest.useFakeTimers());
  afterEach(() => jest.useRealTimers());

  it("returns a short expiry and safely replaces/deletes ephemeral state", async () => {
    const store = new InMemoryTypingStore();
    const start = Date.now();
    const first = await store.set("conversation", "user");
    const second = await store.set("conversation", "user");
    expect(first.getTime()).toBe(start + TYPING_TTL_SECONDS * 1000);
    expect(second.getTime()).toBe(first.getTime());
    await expect(store.delete("conversation", "user")).resolves.toBeUndefined();
    jest.advanceTimersByTime(TYPING_TTL_SECONDS * 1000);
  });
});

describe("RedisTypingStore lifecycle", () => {
  beforeEach(() => redisMock.mockClear());

  it("disconnects a never-connected lazy client without calling quit", async () => {
    const { store, client } = createRedisStore();

    await store.onModuleDestroy();

    expect(client.quit).not.toHaveBeenCalled();
    expect(client.disconnect).toHaveBeenCalledWith(false);
  });

  it("gracefully quits a ready client", async () => {
    const { store, client } = createRedisStore();
    client.status = "ready";
    client.quit.mockResolvedValue("OK");

    await store.onModuleDestroy();

    expect(client.quit).toHaveBeenCalledTimes(1);
    expect(client.disconnect).not.toHaveBeenCalled();
  });

  it("force-disconnects when graceful shutdown fails", async () => {
    const { store, client } = createRedisStore();
    client.status = "ready";
    client.quit.mockRejectedValue(new Error("socket closed"));

    await store.onModuleDestroy();

    expect(client.disconnect).toHaveBeenCalledWith(false);
  });
});
