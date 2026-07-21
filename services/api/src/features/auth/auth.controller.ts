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
import { LogoutDto, RefreshDto, RequestOtpDto, VerifyOtpDto } from "./auth.dto";
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
