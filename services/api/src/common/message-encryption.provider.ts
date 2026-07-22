import { Injectable } from "@nestjs/common";

export const MESSAGE_ENCRYPTION_PROVIDER = Symbol(
  "MESSAGE_ENCRYPTION_PROVIDER",
);

export type MessageMetadata = Record<string, string | number | boolean | null>;

export interface MessageTransportPayload {
  text: string | null;
  metadata: MessageMetadata;
}

export interface ServerManagedMessageEnvelopeV1
  extends MessageTransportPayload {
  mode: "SERVER_MANAGED";
  version: 1;
}

/** Protocol boundary only. No Future E2EE provider is registered in phase 1. */
export interface FutureE2eeMessageEnvelope {
  mode: "FUTURE_E2EE";
  version: number;
  protocol: string;
  ciphertext: string;
}

export interface StoredMessageEnvelope {
  mode: string;
  version: number;
  text: string | null;
  metadata: unknown;
}

export interface MessageEncryptionProvider {
  readonly mode: "SERVER_MANAGED";
  toPersistence(
    payload: MessageTransportPayload,
  ): ServerManagedMessageEnvelopeV1;
  fromPersistence(envelope: StoredMessageEnvelope): MessageTransportPayload;
}

export class UnsupportedMessageEncryptionEnvelopeError extends Error {
  constructor(mode: string, version: number) {
    super(`Unsupported message envelope: ${mode} v${version}`);
    this.name = "UnsupportedMessageEncryptionEnvelopeError";
  }
}

/**
 * Phase-1 server-managed storage. This boundary does not claim or simulate
 * end-to-end encryption; plaintext remains available for authorized search and
 * moderation and is protected by transport/storage controls.
 */
@Injectable()
export class ServerManagedEncryptionProvider
  implements MessageEncryptionProvider
{
  readonly mode = "SERVER_MANAGED" as const;

  toPersistence(
    payload: MessageTransportPayload,
  ): ServerManagedMessageEnvelopeV1 {
    return {
      mode: this.mode,
      version: 1,
      text: payload.text,
      metadata: { ...payload.metadata },
    };
  }

  fromPersistence(envelope: StoredMessageEnvelope): MessageTransportPayload {
    if (envelope.mode !== this.mode || envelope.version !== 1) {
      throw new UnsupportedMessageEncryptionEnvelopeError(
        envelope.mode,
        envelope.version,
      );
    }
    if (
      !envelope.metadata ||
      typeof envelope.metadata !== "object" ||
      Array.isArray(envelope.metadata)
    ) {
      throw new Error("Invalid server-managed message metadata");
    }
    return {
      text: envelope.text,
      metadata: {
        ...(envelope.metadata as MessageMetadata),
      },
    };
  }
}
