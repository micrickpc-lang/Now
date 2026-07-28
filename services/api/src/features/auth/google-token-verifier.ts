import {
  BadRequestException,
  Injectable,
  ServiceUnavailableException,
  UnauthorizedException,
} from "@nestjs/common";
import { ConfigService } from "@nestjs/config";
import { OAuth2Client } from "google-auth-library";

export interface VerifiedGoogleIdentity {
  subject: string;
  email: string;
  name?: string;
}

@Injectable()
export class GoogleTokenVerifier {
  private readonly client = new OAuth2Client();

  constructor(private readonly config: ConfigService) {}

  async verify(idToken: string): Promise<VerifiedGoogleIdentity> {
    const audiences = (this.config.get<string>("GOOGLE_CLIENT_IDS") ?? "")
      .split(",")
      .map((value) => value.trim())
      .filter(Boolean);
    if (audiences.length === 0) {
      throw new ServiceUnavailableException("Google sign-in is not configured");
    }

    try {
      const ticket = await this.client.verifyIdToken({
        idToken,
        audience: audiences,
      });
      const payload = ticket.getPayload();
      if (!payload?.sub || !payload.email || payload.email_verified !== true) {
        throw new BadRequestException("Google account email must be verified");
      }
      return {
        subject: payload.sub,
        email: payload.email,
        name: payload.name,
      };
    } catch (error) {
      if (error instanceof BadRequestException) throw error;
      throw new UnauthorizedException("Invalid Google ID token");
    }
  }
}
