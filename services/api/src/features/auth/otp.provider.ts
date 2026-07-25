import { Inject, Injectable, Logger } from "@nestjs/common";
import { ConfigService } from "@nestjs/config";

export const OTP_PROVIDER = Symbol("OTP_PROVIDER");

export interface OtpProvider {
  send(phone: string, code: string): Promise<void>;
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

  send(phone: string, code: string): Promise<void> {
    if (
      this.config.get("NODE_ENV") !== "development" ||
      this.config.get("ALLOW_DEV_OTP") !== "true"
    ) {
      throw new Error("Development OTP provider is disabled");
    }
    void phone;
    void code;
    this.logger.warn({ event: "development_otp_dispatched" });
    return Promise.resolve();
  }
}

@Injectable()
export class StagingOtpProvider implements OtpProvider {
  constructor(private readonly config: ConfigService) {}

  send(phone: string, code: string): Promise<void> {
    if (this.config.get("APP_ENV") !== "staging") {
      throw new Error("Staging OTP provider is disabled");
    }
    if (!stagingPhoneAllowlist(this.config).has(phone)) {
      // Keep the public OTP response indistinguishable while no real SMS
      // provider is connected to staging.
      return Promise.resolve();
    }
    if (code !== this.config.getOrThrow<string>("STAGING_TEST_OTP")) {
      throw new Error("Invalid staging OTP dispatch configuration");
    }
    return Promise.resolve();
  }
}

export abstract class ProductionOtpProvider implements OtpProvider {
  abstract send(phone: string, code: string): Promise<void>;
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
  send(phone: string, code: string) {
    return this.provider.send(phone, code);
  }
}
