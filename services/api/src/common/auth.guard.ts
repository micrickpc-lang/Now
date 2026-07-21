import {
  CanActivate,
  ExecutionContext,
  Injectable,
  UnauthorizedException,
} from "@nestjs/common";
import { Reflector } from "@nestjs/core";
import type { Request } from "express";
import { TokenService } from "../features/auth/token.service";
import type { AuthenticatedRequest } from "./http";

@Injectable()
export class AccessTokenGuard implements CanActivate {
  constructor(
    private readonly reflector: Reflector,
    private readonly tokens: TokenService,
  ) {}

  canActivate(context: ExecutionContext): boolean {
    if (
      this.reflector.getAllAndOverride<boolean>("public", [
        context.getHandler(),
        context.getClass(),
      ])
    ) {
      return true;
    }
    const request = context.switchToHttp().getRequest<Request>();
    const header = request.headers.authorization;
    if (!header?.startsWith("Bearer "))
      throw new UnauthorizedException("Authentication required");
    const payload = this.tokens.verifyAccess(header.slice(7));
    (request as AuthenticatedRequest).auth = {
      userId: payload.sub,
      sessionId: payload.sid,
    };
    return true;
  }
}
