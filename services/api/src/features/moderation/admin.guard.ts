import {
  CanActivate,
  ExecutionContext,
  Injectable,
  UnauthorizedException,
} from "@nestjs/common";
import type { Request } from "express";
import { AdminAuthService, type AdminPayload } from "./admin-auth.service";

export interface AdminRequest extends Request {
  admin: AdminPayload;
}

@Injectable()
export class AdminGuard implements CanActivate {
  constructor(private readonly auth: AdminAuthService) {}
  canActivate(context: ExecutionContext): boolean {
    const request = context.switchToHttp().getRequest<Request>();
    const header = request.headers.authorization;
    if (!header?.startsWith("Bearer ")) throw new UnauthorizedException();
    (request as AdminRequest).admin = this.auth.verify(header.slice(7));
    return true;
  }
}
