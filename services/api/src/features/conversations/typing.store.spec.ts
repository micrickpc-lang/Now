import { InMemoryTypingStore, TYPING_TTL_SECONDS } from "./typing.store";

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
