import { Type } from "class-transformer";
import {
  IsDateString,
  IsIn,
  IsOptional,
  IsString,
  Length,
  MaxLength,
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
