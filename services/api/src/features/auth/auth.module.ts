import { Module } from "@nestjs/common";
import { ConfigService } from "@nestjs/config";
import { AuthController } from "./auth.controller";
import { AuthService } from "./auth.service";
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
    OtpDispatcher,
    DevelopmentOtpProvider,
    UnconfiguredProductionOtpProvider,
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
