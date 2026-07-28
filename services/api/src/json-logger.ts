import type { LoggerService } from "@nestjs/common";

const sensitiveKey =
  /^(accessToken|refreshToken|token|authorization|password|code|email|phone|latitude|longitude|location|message|body|text|payload|ciphertext)$/iu;

export const redactForLogs = (value: unknown, key?: string): unknown => {
  if (key && sensitiveKey.test(key)) return "[REDACTED]";
  if (typeof value === "string") {
    return value
      .replace(/Bearer\s+[A-Za-z0-9._-]+/gu, "Bearer [REDACTED]")
      .replace(
        /\b[A-Z0-9._%+-]+@[A-Z0-9.-]+\.[A-Z]{2,}\b/giu,
        "[EMAIL_REDACTED]",
      )
      .replace(/\+?\d[\d\s()-]{7,}/gu, "[PHONE_REDACTED]")
      .replace(
        /\b(latitude|longitude|lat|lon|code|token|password|message|body|text)\s*[:=]\s*[^\s,;]+/giu,
        "$1=[REDACTED]",
      );
  }
  if (Array.isArray(value)) return value.map((entry) => redactForLogs(entry));
  if (value && typeof value === "object") {
    return Object.fromEntries(
      Object.entries(value).map(([entryKey, entryValue]) => [
        entryKey,
        redactForLogs(entryValue, entryKey),
      ]),
    );
  }
  return value;
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
      message: redactForLogs(message),
      ...(trace && { trace: redactForLogs(trace) }),
    });
    if (level === "error") process.stderr.write(`${entry}\n`);
    else process.stdout.write(`${entry}\n`);
  }
}
