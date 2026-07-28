import { Module } from "@nestjs/common";
import { ConfigService } from "@nestjs/config";
import { AuthController } from "./auth.controller";
import { AuthService } from "./auth.service";
import {
  HttpSmsProvider,
  LocalTestSmsProvider,
  OTP_PROVIDER,
  OtpDispatcher,
  SmsRuOtpProvider,
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
    LocalTestSmsProvider,
    HttpSmsProvider,
    StagingOtpProvider,
    SmsRuOtpProvider,
    UnconfiguredProductionOtpProvider,
    {
      provide: OTP_PROVIDER,
      inject: [
        ConfigService,
        LocalTestSmsProvider,
        HttpSmsProvider,
        StagingOtpProvider,
        SmsRuOtpProvider,
        UnconfiguredProductionOtpProvider,
      ],
      useFactory: (
        config: ConfigService,
        localTest: LocalTestSmsProvider,
        http: HttpSmsProvider,
        staging: StagingOtpProvider,
        smsRu: SmsRuOtpProvider,
        production: UnconfiguredProductionOtpProvider,
      ) => {
        const authMode = config.get<string>("AUTH_MODE");
        if (authMode === "local_test") return localTest;
        if (authMode === "real_sms") return http;
        if (config.get<string>("SMS_PROVIDER") === "smsru") return smsRu;
        const appEnvironment = config.get<string>("APP_ENV");
        if (appEnvironment === "staging") return staging;
        return production;
      },
    },
  ],
  exports: [TokenService],
})
export class AuthModule {}
