import {
  CallHandler,
  ExecutionContext,
  HttpException,
  Injectable,
  Logger,
  NestInterceptor,
} from "@nestjs/common";
import type { Response } from "express";
import type { Observable } from "rxjs";
import { catchError, finalize, throwError } from "rxjs";
import { CryptoService } from "./crypto.service";
import type { RequestWithContext } from "./request-context.middleware";

@Injectable()
export class SafeHttpLoggingInterceptor implements NestInterceptor {
  private readonly logger = new Logger("HttpRequest");

  constructor(private readonly crypto: CryptoService) {}

  intercept(context: ExecutionContext, next: CallHandler): Observable<unknown> {
    if (context.getType() !== "http") return next.handle();
    const request = context.switchToHttp().getRequest<RequestWithContext>();
    const response = context.switchToHttp().getResponse<Response>();
    const startedAt = Date.now();
    let errorStatus: number | undefined;

    return next.handle().pipe(
      catchError((error: unknown) => {
        errorStatus = error instanceof HttpException ? error.getStatus() : 500;
        return throwError(() => error);
      }),
      finalize(() => {
        this.logger.log({
          event: "http_request",
          requestId: request.requestId,
          method: request.method,
          endpoint: request.path,
          statusCode: errorStatus ?? response.statusCode,
          durationMs: Date.now() - startedAt,
          ...(request.auth?.userId && {
            userRef: this.crypto
              .hashToken(`http-log:${request.auth.userId}`)
              .slice(0, 20),
          }),
        });
      }),
    );
  }
}
