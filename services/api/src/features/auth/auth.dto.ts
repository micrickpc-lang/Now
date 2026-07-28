import { Type } from "class-transformer";
import {
  IsDateString,
  IsEmail,
  IsIn,
  IsOptional,
  IsString,
  Length,
  MaxLength,
  Matches,
} from "class-validator";

export class RequestOtpDto {
  @IsString()
  @MaxLength(30)
  phone!: string;
}

export class VerifyOtpDto {
  @IsString()
  @MaxLength(30)
  phone!: string;

  @IsString()
  @Length(6, 6)
  code!: string;

  @IsDateString()
  birthDate!: string;

  @IsString()
  @Length(2, 40)
  displayName!: string;

  @IsString()
  @Length(8, 128)
  installationId!: string;

  @IsIn(["android", "ios", "web"])
  platform!: string;

  @IsOptional()
  @IsString()
  @MaxLength(80)
  deviceLabel?: string;
}

export class RequestEmailCodeDto {
  @IsEmail()
  @MaxLength(254)
  email!: string;
}

export class VerifyEmailCodeDto extends RequestEmailCodeDto {
  @IsString()
  @Length(6, 6)
  code!: string;

  @IsString()
  @Length(8, 128)
  installationId!: string;

  @IsIn(["android", "ios", "web"])
  platform!: string;

  @IsOptional()
  @IsString()
  @MaxLength(80)
  deviceLabel?: string;

  @IsOptional()
  @IsString()
  @MaxLength(40)
  appVersion?: string;
}

export class GoogleAuthDto {
  @IsString()
  @Length(20, 8192)
  idToken!: string;

  @IsString()
  @Length(8, 128)
  installationId!: string;

  @IsIn(["android", "ios", "web"])
  platform!: string;

  @IsOptional()
  @IsString()
  @MaxLength(80)
  deviceLabel?: string;

  @IsOptional()
  @IsString()
  @MaxLength(40)
  appVersion?: string;
}

export class LinkGoogleDto {
  @IsString()
  @Length(20, 8192)
  idToken!: string;
}

export class CompleteProfileDto {
  @IsString()
  @Length(2, 40)
  displayName!: string;

  @IsString()
  @Matches(/^[a-z0-9_]{3,32}$/)
  username!: string;
}

export class RefreshDto {
  @IsString()
  @Length(32, 512)
  refreshToken!: string;
}

export class LogoutDto extends RefreshDto {}

export class SessionIdDto {
  @Type(() => String)
  @IsString()
  id!: string;
}
