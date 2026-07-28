import {
  ArgumentsHost,
  Catch,
  ExceptionFilter,
  HttpException,
  HttpStatus,
  Logger,
} from "@nestjs/common";
import type { Response } from "express";
import type { RequestWithContext } from "./request-context.middleware";

interface ErrorEnvelope {
  code: string;
  message: string;
  requestId: string;
  details?: string[];
}

const statusCodes: Partial<Record<number, string>> = {
  [HttpStatus.BAD_REQUEST]: "VALIDATION_ERROR",
  [HttpStatus.UNAUTHORIZED]: "AUTHENTICATION_REQUIRED",
  [HttpStatus.FORBIDDEN]: "ACCESS_DENIED",
  [HttpStatus.NOT_FOUND]: "NOT_FOUND",
  [HttpStatus.CONFLICT]: "CONFLICT",
  [HttpStatus.TOO_MANY_REQUESTS]: "RATE_LIMITED",
  [HttpStatus.BAD_GATEWAY]: "UPSTREAM_UNAVAILABLE",
  [HttpStatus.SERVICE_UNAVAILABLE]: "SERVICE_UNAVAILABLE",
};

@Catch()
export class SafeExceptionFilter implements ExceptionFilter {
  private readonly logger = new Logger("HttpException");

  catch(exception: unknown, host: ArgumentsHost) {
    const context = host.switchToHttp();
    const request = context.getRequest<RequestWithContext>();
    const response = context.getResponse<Response>();
    const isHttp = exception instanceof HttpException;
    const status = isHttp
      ? exception.getStatus()
      : HttpStatus.INTERNAL_SERVER_ERROR;
    const raw = isHttp ? exception.getResponse() : undefined;
    const object =
      typeof raw === "object" && raw !== null
        ? (raw as Record<string, unknown>)
        : undefined;
    const explicitCode =
      typeof object?.code === "string" ? object.code : undefined;
    const validationDetails = Array.isArray(object?.message)
      ? object.message.filter(
          (item): item is string => typeof item === "string",
        )
      : undefined;
    const staticMessage =
      status >= 500
        ? "Service is temporarily unavailable"
        : typeof raw === "string"
          ? raw
          : typeof object?.message === "string"
            ? object.message
            : validationDetails
              ? "Request validation failed"
              : "Request failed";
    const envelope: ErrorEnvelope = {
      code:
        explicitCode ??
        statusCodes[status] ??
        (status >= 500 ? "INTERNAL_ERROR" : "REQUEST_FAILED"),
      message: staticMessage,
      requestId: request.requestId,
      ...(validationDetails?.length && { details: validationDetails }),
    };

    this.logger[status >= 500 ? "error" : "warn"]({
      event: "http_error",
      requestId: request.requestId,
      method: request.method,
      endpoint: request.path,
      statusCode: status,
      errorCode: envelope.code,
      errorType:
        exception instanceof Error ? exception.name : "UnknownException",
    });
    response.status(status).json(envelope);
  }
}
