import { Inject, Injectable, Logger } from "@nestjs/common";
import { ConfigService } from "@nestjs/config";

export const OTP_PROVIDER = Symbol("OTP_PROVIDER");

export type SmsOtpInput = {
  phoneE164: string;
  code: string;
  requestId: string;
};

/**
 * Provider-neutral OTP delivery boundary. The HTTP adapter sends a JSON POST
 * with Bearer authentication; providers with another wire format only need a
 * separate implementation of this interface.
 */
export interface SmsProvider {
  sendOtp(input: SmsOtpInput): Promise<void>;
}

export function stagingPhoneAllowlist(config: ConfigService): Set<string> {
  return new Set(
    (config.get<string>("STAGING_TEST_PHONE_ALLOWLIST") ?? "")
      .split(",")
      .map((phone) => phone.trim())
      .filter(Boolean),
  );
}

@Injectable()
export class LocalTestSmsProvider implements SmsProvider {
  private readonly logger = new Logger(LocalTestSmsProvider.name);

  constructor(private readonly config: ConfigService) {}

  sendOtp(input: SmsOtpInput): Promise<void> {
    if (
      this.config.get("NODE_ENV") !== "development" ||
      this.config.get("APP_ENV") !== "development" ||
      this.config.get("AUTH_MODE") !== "local_test" ||
      this.config.get("ALLOW_LOCAL_TEST_OTP") !== "true"
    ) {
      return Promise.reject(new Error("Local test SMS provider is disabled"));
    }
    // Do not log phone numbers or OTPs, even in the local-only transport.
    this.logger.log({
      event: "local_test_otp_dispatched",
      requestId: input.requestId,
    });
    return Promise.resolve();
  }
}

type HttpSmsResponse = {
  success?: unknown;
  error?: unknown;
  id?: unknown;
  messageId?: unknown;
};

/**
 * Generic provider contract: POST `SMS_API_BASE_URL` with JSON
 * `{ to, from, message, requestId }`, `Authorization: Bearer SMS_API_KEY`,
 * and `Idempotency-Key: requestId`. Any 2xx response is accepted unless JSON
 * explicitly contains `success: false` or `error`; optional `id`/`messageId`
 * values are recorded as the provider delivery identifier.
 */
@Injectable()
export class HttpSmsProvider implements SmsProvider {
  private readonly logger = new Logger(HttpSmsProvider.name);

  constructor(private readonly config: ConfigService) {}

  async sendOtp(input: SmsOtpInput): Promise<void> {
    const controller = new AbortController();
    const timeout = setTimeout(
      () => controller.abort(),
      Number(this.config.get("SMS_TIMEOUT_MS") ?? "10000"),
    );
    let response: Response;
    try {
      response = await fetch(
        this.config.getOrThrow<string>("SMS_API_BASE_URL"),
        {
          method: "POST",
          headers: {
            authorization: `Bearer ${this.config.getOrThrow<string>("SMS_API_KEY")}`,
            "content-type": "application/json",
            "idempotency-key": input.requestId,
          },
          body: JSON.stringify({
            to: input.phoneE164,
            from: this.config.getOrThrow<string>("SMS_SENDER"),
            message: this.config
              .getOrThrow<string>("SMS_TEMPLATE")
              .replaceAll("{code}", input.code),
            requestId: input.requestId,
          }),
          signal: controller.signal,
        },
      );
    } catch {
      throw new Error("SMS provider request failed");
    } finally {
      clearTimeout(timeout);
    }

    let payload: HttpSmsResponse | undefined;
    try {
      payload = (await response.json()) as HttpSmsResponse;
    } catch {
      // A successful 2xx response without JSON is valid for providers that do
      // not expose a delivery identifier.
    }
    if (!response.ok || payload?.success === false || payload?.error) {
      throw new Error("SMS provider rejected the message");
    }

    const providerMessageId = payload?.messageId ?? payload?.id;
    this.logger.log({
      event: "sms_provider_accepted",
      requestId: input.requestId,
      ...(typeof providerMessageId === "string" ? { providerMessageId } : {}),
    });
  }
}

/** Test-only provider. It is intentionally not registered by AuthModule. */
export class FakeSmsProvider implements SmsProvider {
  readonly sent: SmsOtpInput[] = [];
  failWith?: Error;

  sendOtp(input: SmsOtpInput): Promise<void> {
    if (this.failWith) return Promise.reject(this.failWith);
    this.sent.push({ ...input });
    return Promise.resolve();
  }
}

@Injectable()
export class StagingOtpProvider implements SmsProvider {
  constructor(private readonly config: ConfigService) {}

  sendOtp(input: SmsOtpInput): Promise<void> {
    if (this.config.get("APP_ENV") !== "staging") {
      return Promise.reject(new Error("Staging OTP provider is disabled"));
    }
    if (!stagingPhoneAllowlist(this.config).has(input.phoneE164)) {
      return Promise.reject(
        new Error("Real SMS is not configured for this staging number"),
      );
    }
    if (input.code !== this.config.getOrThrow<string>("STAGING_TEST_OTP")) {
      return Promise.reject(
        new Error("Invalid staging OTP dispatch configuration"),
      );
    }
    return Promise.resolve();
  }
}

type SmsRuResponse = {
  status?: unknown;
  status_code?: unknown;
  sms?: Record<
    string,
    {
      status?: unknown;
      status_code?: unknown;
    }
  >;
};

@Injectable()
export class SmsRuOtpProvider implements SmsProvider {
  private static readonly endpoint = "https://sms.ru/sms/send";

  constructor(private readonly config: ConfigService) {}

  async sendOtp(input: SmsOtpInput): Promise<void> {
    if (
      this.config.get<string>("APP_ENV") === "staging" &&
      stagingPhoneAllowlist(this.config).has(input.phoneE164)
    ) {
      return;
    }

    const target = input.phoneE164.replace(/^\+/u, "");
    const ttlSeconds = Number(this.config.get("OTP_TTL_SECONDS") ?? "300");
    const body = new URLSearchParams({
      api_id: this.config.getOrThrow<string>("SMS_RU_API_ID"),
      to: target,
      msg: `Код для входа в «Сейчас»: ${input.code}. Никому его не сообщайте.`,
      json: "1",
      ttl: String(Math.max(1, Math.min(1440, Math.ceil(ttlSeconds / 60)))),
    });
    const sender = this.config.get<string>("SMS_RU_FROM")?.trim();
    if (sender) body.set("from", sender);

    const controller = new AbortController();
    const timeout = setTimeout(
      () => controller.abort(),
      Number(this.config.get("SMS_RU_TIMEOUT_MS") ?? "5000"),
    );
    let response: Response;
    try {
      response = await fetch(SmsRuOtpProvider.endpoint, {
        method: "POST",
        headers: { "content-type": "application/x-www-form-urlencoded" },
        body: body.toString(),
        signal: controller.signal,
      });
    } catch {
      throw new Error("SMS provider request failed");
    } finally {
      clearTimeout(timeout);
    }
    if (!response.ok) throw new Error("SMS provider request failed");

    let payload: SmsRuResponse;
    try {
      payload = (await response.json()) as SmsRuResponse;
    } catch {
      throw new Error("SMS provider returned an invalid response");
    }
    const delivery = payload.sms?.[target];
    if (
      payload.status !== "OK" ||
      payload.status_code !== 100 ||
      delivery?.status !== "OK" ||
      delivery.status_code !== 100
    ) {
      throw new Error("SMS provider rejected the message");
    }
  }
}

@Injectable()
export class UnconfiguredProductionOtpProvider implements SmsProvider {
  sendOtp(): Promise<void> {
    return Promise.reject(
      new Error("Production SMS provider is not configured"),
    );
  }
}

@Injectable()
export class OtpDispatcher {
  constructor(@Inject(OTP_PROVIDER) private readonly provider: SmsProvider) {}

  sendOtp(input: SmsOtpInput) {
    return this.provider.sendOtp(input);
  }
}
