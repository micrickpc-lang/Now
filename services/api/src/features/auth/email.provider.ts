import {
  Inject,
  Injectable,
  ServiceUnavailableException,
} from "@nestjs/common";
import { ConfigService } from "@nestjs/config";
import nodemailer from "nodemailer";

export const EMAIL_PROVIDER = Symbol("EMAIL_PROVIDER");

export interface EmailProvider {
  sendLoginCode(email: string, code: string): Promise<void>;
}

@Injectable()
export class SmtpEmailProvider implements EmailProvider {
  constructor(private readonly config: ConfigService) {}

  async sendLoginCode(email: string, code: string): Promise<void> {
    const smtpUrl = this.config.get<string>("SMTP_URL");
    const from = this.config.get<string>("EMAIL_FROM");
    if (!smtpUrl || !from) {
      throw new ServiceUnavailableException("Email delivery is not configured");
    }
    const transport = nodemailer.createTransport(smtpUrl);
    await transport.sendMail({
      from,
      to: email,
      subject: "Your Seychas sign-in code",
      text: `Your sign-in code is ${code}. It expires in 10 minutes.`,
    });
  }
}

@Injectable()
export class DisabledEmailProvider implements EmailProvider {
  async sendLoginCode(): Promise<void> {
    // Explicitly limited to non-production test environments by configuration.
  }
}

@Injectable()
export class EmailDispatcher {
  constructor(
    @Inject(EMAIL_PROVIDER) private readonly provider: EmailProvider,
  ) {}

  sendLoginCode(email: string, code: string): Promise<void> {
    return this.provider.sendLoginCode(email, code);
  }
}
