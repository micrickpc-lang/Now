import type { LoggerService } from "@nestjs/common";

const redact = (value: unknown): unknown => {
  if (typeof value !== "string") return value;
  return value
    .replace(/Bearer\s+[A-Za-z0-9._-]+/gu, "Bearer [REDACTED]")
    .replace(/\+?\d[\d\s()-]{7,}/gu, "[PHONE_REDACTED]");
};

export class JsonLogger implements LoggerService {
  log(message: unknown, context?: string) {
    this.write("info", message, context);
  }
  error(message: unknown, trace?: string, context?: string) {
    this.write("error", message, context, trace);
  }
  warn(message: unknown, context?: string) {
    this.write("warn", message, context);
  }
  debug(message: unknown, context?: string) {
    this.write("debug", message, context);
  }
  verbose(message: unknown, context?: string) {
    this.write("trace", message, context);
  }

  private write(
    level: string,
    message: unknown,
    context?: string,
    trace?: string,
  ) {
    const entry = JSON.stringify({
      level,
      time: new Date().toISOString(),
      context,
      message: redact(message),
      ...(trace && { trace }),
    });
    if (level === "error") process.stderr.write(`${entry}\n`);
    else process.stdout.write(`${entry}\n`);
  }
}
