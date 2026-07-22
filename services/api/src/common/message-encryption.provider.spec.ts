import {
  ServerManagedEncryptionProvider,
  UnsupportedMessageEncryptionEnvelopeError,
} from "./message-encryption.provider";

describe("ServerManagedEncryptionProvider", () => {
  const provider = new ServerManagedEncryptionProvider();

  it("uses an explicit versioned server-managed envelope", () => {
    const stored = provider.toPersistence({
      text: "searchable text",
      metadata: { signalId: "signal" },
    });
    expect(stored).toEqual({
      mode: "SERVER_MANAGED",
      version: 1,
      text: "searchable text",
      metadata: { signalId: "signal" },
    });
    expect(provider.fromPersistence(stored)).toEqual({
      text: "searchable text",
      metadata: { signalId: "signal" },
    });
  });

  it("does not silently treat a future E2EE envelope as server-managed", () => {
    expect(() =>
      provider.fromPersistence({
        mode: "FUTURE_E2EE",
        version: 1,
        text: null,
        metadata: {},
      }),
    ).toThrow(UnsupportedMessageEncryptionEnvelopeError);
  });
});
