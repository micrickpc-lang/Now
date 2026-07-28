import {
  Body,
  Controller,
  Delete,
  Get,
  Headers,
  Param,
  Post,
  Req,
} from "@nestjs/common";
import { ApiBearerAuth, ApiTags } from "@nestjs/swagger";
import type { Request } from "express";
import { CurrentAuth, Public, requestIp } from "../../common/http";
import {
  CompleteProfileDto,
  GoogleAuthDto,
  LinkGoogleDto,
  LogoutDto,
  RefreshDto,
  RequestEmailCodeDto,
  RequestOtpDto,
  VerifyEmailCodeDto,
  VerifyOtpDto,
} from "./auth.dto";
import { AuthService } from "./auth.service";

@ApiTags("auth")
@Controller("auth")
export class AuthController {
  constructor(private readonly auth: AuthService) {}

  @Public()
  @Post("otp/request")
  requestOtp(@Body() dto: RequestOtpDto, @Req() request: Request) {
    return this.auth.requestOtp(dto.phone, requestIp(request));
  }

  @Public()
  @Post("otp/verify")
  verifyOtp(
    @Body() dto: VerifyOtpDto,
    @Req() request: Request,
    @Headers("user-agent") userAgent?: string,
  ) {
    return this.auth.verifyOtp(dto, requestIp(request), userAgent);
  }

  @Public()
  @Post("email/request-code")
  requestEmailCode(@Body() dto: RequestEmailCodeDto, @Req() request: Request) {
    return this.auth.requestEmailCode(dto, requestIp(request));
  }

  @Public()
  @Post("email/resend-code")
  resendEmailCode(@Body() dto: RequestEmailCodeDto, @Req() request: Request) {
    return this.auth.resendEmailCode(dto, requestIp(request));
  }

  @Public()
  @Post("email/verify-code")
  verifyEmailCode(
    @Body() dto: VerifyEmailCodeDto,
    @Req() request: Request,
    @Headers("user-agent") userAgent?: string,
  ) {
    return this.auth.verifyEmailCode(dto, requestIp(request), userAgent);
  }

  @Public()
  @Post("google")
  google(
    @Body() dto: GoogleAuthDto,
    @Req() request: Request,
    @Headers("user-agent") userAgent?: string,
  ) {
    return this.auth.signInWithGoogle(dto, requestIp(request), userAgent);
  }

  @Public()
  @Post("refresh")
  refresh(@Body() dto: RefreshDto, @Req() request: Request) {
    return this.auth.refresh(dto.refreshToken, requestIp(request));
  }

  @ApiBearerAuth()
  @Post("logout")
  logout(@CurrentAuth() current: { userId: string }, @Body() dto: LogoutDto) {
    return this.auth.logout(current.userId, dto.refreshToken);
  }

  @ApiBearerAuth()
  @Post("logout-all")
  logoutAll(@CurrentAuth() current: { userId: string }) {
    return this.auth.logoutAll(current.userId);
  }

  @ApiBearerAuth()
  @Post("profile")
  completeProfile(
    @CurrentAuth() current: { userId: string },
    @Body() dto: CompleteProfileDto,
  ) {
    return this.auth.completeProfile(current.userId, dto);
  }

  @ApiBearerAuth()
  @Get("identities")
  identities(@CurrentAuth() current: { userId: string }) {
    return this.auth.identities(current.userId);
  }

  @ApiBearerAuth()
  @Post("identities/email/request-code")
  requestEmailIdentityLink(
    @CurrentAuth() current: { userId: string },
    @Body() dto: RequestEmailCodeDto,
    @Req() request: Request,
  ) {
    return this.auth.requestEmailIdentityLink(
      current.userId,
      dto,
      requestIp(request),
    );
  }

  @ApiBearerAuth()
  @Post("identities/email/verify-code")
  verifyEmailIdentityLink(
    @CurrentAuth() current: { userId: string },
    @Body() dto: VerifyEmailCodeDto,
  ) {
    return this.auth.verifyEmailIdentityLink(current.userId, dto);
  }

  @ApiBearerAuth()
  @Post("identities/google")
  linkGoogleIdentity(
    @CurrentAuth() current: { userId: string },
    @Body() dto: LinkGoogleDto,
  ) {
    return this.auth.linkGoogleIdentity(current.userId, dto.idToken);
  }

  @ApiBearerAuth()
  @Delete("identities/:provider")
  unlinkIdentity(
    @CurrentAuth() current: { userId: string },
    @Param("provider") provider: string,
  ) {
    return this.auth.unlinkIdentity(current.userId, provider);
  }

  @ApiBearerAuth()
  @Get("sessions")
  sessions(@CurrentAuth() current: { userId: string }) {
    return this.auth.sessions(current.userId);
  }

  @ApiBearerAuth()
  @Delete("sessions/:id")
  revoke(@CurrentAuth() current: { userId: string }, @Param("id") id: string) {
    return this.auth.revokeSession(current.userId, id);
  }
}
