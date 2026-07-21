export interface PushMessage {
  recipientId: string;
  category: "signal" | "join" | "reminder";
  title: string;
  body: string;
  entityId?: string;
}

export interface PushProvider {
  send(message: PushMessage): Promise<void>;
}

const forbiddenPushKeys = [
  "latitude",
  "longitude",
  "phone",
  "token",
  "messageText",
  "inviteToken",
];

export abstract class ValidatingPushProvider implements PushProvider {
  async send(message: PushMessage): Promise<void> {
    const serialized = JSON.stringify(message).toLocaleLowerCase("en-US");
    if (
      forbiddenPushKeys.some((key) =>
        serialized.includes(key.toLocaleLowerCase("en-US")),
      )
    ) {
      throw new Error("Sensitive data in push payload");
    }
    await this.deliver(message);
  }

  protected abstract deliver(message: PushMessage): Promise<void>;
}

export class DisabledPushProvider extends ValidatingPushProvider {
  protected async deliver(): Promise<void> {
    // Deliberately no-op until a production provider is configured by dependency injection.
  }
}
