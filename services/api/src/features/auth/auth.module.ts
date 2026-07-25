import { Module } from "@nestjs/common";
import { ConfigService } from "@nestjs/config";
import { AuthController } from "./auth.controller";
import { AuthService } from "./auth.service";
import {
  DevelopmentOtpProvider,
  OTP_PROVIDER,
  OtpDispatcher,
  StagingOtpProvider,
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
    StagingOtpProvider,
    UnconfiguredProductionOtpProvider,
    {
      provide: OTP_PROVIDER,
      inject: [
        ConfigService,
        DevelopmentOtpProvider,
        StagingOtpProvider,
        UnconfiguredProductionOtpProvider,
      ],
      useFactory: (
        config: ConfigService,
        development: DevelopmentOtpProvider,
        staging: StagingOtpProvider,
        production: UnconfiguredProductionOtpProvider,
      ) => {
        const appEnvironment = config.get<string>("APP_ENV");
        if (appEnvironment === "staging") return staging;
        if (appEnvironment === "production") return production;
        return development;
      },
    },
  ],
  exports: [TokenService],
})
export class AuthModule {}
