import { Inject, Injectable } from "@nestjs/common";
import { ConfigService } from "@nestjs/config";

export const OTP_PROVIDER = Symbol("OTP_PROVIDER");

export interface OtpProvider {
  send(phone: string, code: string): Promise<void>;
}

@Injectable()
export class DevelopmentOtpProvider implements OtpProvider {
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
