import { Module } from "@nestjs/common";
import { ConfigService } from "@nestjs/config";
import { AuthController } from "./auth.controller";
import { AuthService } from "./auth.service";
import {
  DisabledEmailProvider,
  EMAIL_PROVIDER,
  EmailDispatcher,
  SmtpEmailProvider,
} from "./email.provider";
import { GoogleTokenVerifier } from "./google-token-verifier";
import {
  DevelopmentOtpProvider,
  OTP_PROVIDER,
  OtpDispatcher,
  UnconfiguredProductionOtpProvider,
} from "./otp.provider";
import { TokenService } from "./token.service";

@Module({
  controllers: [AuthController],
  providers: [
    AuthService,
    TokenService,
    GoogleTokenVerifier,
    EmailDispatcher,
    SmtpEmailProvider,
    DisabledEmailProvider,
    OtpDispatcher,
    DevelopmentOtpProvider,
    UnconfiguredProductionOtpProvider,
    {
      provide: EMAIL_PROVIDER,
      inject: [ConfigService, SmtpEmailProvider, DisabledEmailProvider],
      useFactory: (
        config: ConfigService,
        smtp: SmtpEmailProvider,
        disabled: DisabledEmailProvider,
      ) => (config.get("EMAIL_DELIVERY_MODE") === "disabled" ? disabled : smtp),
    },
    {
      provide: OTP_PROVIDER,
      inject: [
        ConfigService,
        DevelopmentOtpProvider,
        UnconfiguredProductionOtpProvider,
      ],
      useFactory: (
        config: ConfigService,
        development: DevelopmentOtpProvider,
        production: UnconfiguredProductionOtpProvider,
      ) => (config.get("NODE_ENV") === "production" ? production : development),
    },
  ],
  exports: [TokenService],
})
export class AuthModule {}
