import { Inject, Injectable, Logger } from "@nestjs/common";
import { ConfigService } from "@nestjs/config";
import { isIP } from "node:net";

export const OTP_PROVIDER = Symbol("OTP_PROVIDER");

export type OtpDispatchContext = {
  requestIp: string;
};

export interface OtpProvider {
  send(phone: string, code: string, context: OtpDispatchContext): Promise<void>;
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
export class DevelopmentOtpProvider implements OtpProvider {
  private readonly logger = new Logger("DevelopmentOtpProvider");

  constructor(private readonly config: ConfigService) {}

  send(
    phone: string,
    code: string,
    context: OtpDispatchContext,
  ): Promise<void> {
    if (
      this.config.get("NODE_ENV") !== "development" ||
      this.config.get("ALLOW_DEV_OTP") !== "true"
    ) {
      throw new Error("Development OTP provider is disabled");
    }
    void phone;
    void code;
    void context;
    this.logger.warn({ event: "development_otp_dispatched" });
    return Promise.resolve();
  }
}

@Injectable()
export class StagingOtpProvider implements OtpProvider {
  constructor(private readonly config: ConfigService) {}

  send(
    phone: string,
    code: string,
    context: OtpDispatchContext,
  ): Promise<void> {
    if (this.config.get("APP_ENV") !== "staging") {
      throw new Error("Staging OTP provider is disabled");
    }
    if (!stagingPhoneAllowlist(this.config).has(phone)) {
      return Promise.reject(
        new Error("Real SMS is not configured for this staging number"),
      );
    }
    if (code !== this.config.getOrThrow<string>("STAGING_TEST_OTP")) {
      throw new Error("Invalid staging OTP dispatch configuration");
    }
    void context;
    return Promise.resolve();
  }
}

export abstract class ProductionOtpProvider implements OtpProvider {
  abstract send(
    phone: string,
    code: string,
    context: OtpDispatchContext,
  ): Promise<void>;
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
export class SmsRuOtpProvider extends ProductionOtpProvider {
  private static readonly endpoint = "https://sms.ru/sms/send";

  constructor(private readonly config: ConfigService) {
    super();
  }

  async send(
    phone: string,
    code: string,
    context: OtpDispatchContext,
  ): Promise<void> {
    if (
      this.config.get<string>("APP_ENV") === "staging" &&
      stagingPhoneAllowlist(this.config).has(phone)
    ) {
      return;
    }

    const target = phone.replace(/^\+/u, "");
    const ttlSeconds = Number(this.config.get("OTP_TTL_SECONDS") ?? "300");
    const body = new URLSearchParams({
      api_id: this.config.getOrThrow<string>("SMS_RU_API_ID"),
      to: target,
      msg: `Код для входа в «Сейчас»: ${code}. Никому его не сообщайте.`,
      json: "1",
      ttl: String(Math.max(1, Math.min(1440, Math.ceil(ttlSeconds / 60)))),
    });
    const sender = this.config.get<string>("SMS_RU_FROM")?.trim();
    if (sender) body.set("from", sender);
    if (isIP(context.requestIp)) body.set("ip", context.requestIp);

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
export class UnconfiguredProductionOtpProvider extends ProductionOtpProvider {
  send(): Promise<void> {
    return Promise.reject(
      new Error("Production SMS provider is not configured"),
    );
  }
}

@Injectable()
export class OtpDispatcher {
  constructor(@Inject(OTP_PROVIDER) private readonly provider: OtpProvider) {}
  send(phone: string, code: string, context: OtpDispatchContext) {
    return this.provider.send(phone, code, context);
  }
}
