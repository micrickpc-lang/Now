import {
  IsIn,
  IsOptional,
  IsString,
  IsUUID,
  Length,
  MaxLength,
} from "class-validator";

const categories = [
  "spam",
  "fraud",
  "threats",
  "harassment",
  "doxxing",
  "unsafe_meeting",
  "content",
  "impersonation",
  "other",
];

export class CreateReportDto {
  @IsOptional()
  @IsUUID()
  reportedUserId?: string;

  @IsOptional()
  @IsUUID()
  signalId?: string;

  @IsOptional()
  @IsUUID()
  messageId?: string;

  @IsOptional()
  @IsUUID()
  chatMessageId?: string;

  @IsIn(categories)
  category!: string;

  @IsOptional()
  @IsString()
  @MaxLength(1000)
  details?: string;
}

export class ModerateReportDto {
  @IsIn(["investigate", "dismiss", "warn", "suspend", "mute", "restore"])
  action!: string;

  @IsString()
  @Length(5, 500)
  reason!: string;
}

export class ForbiddenWordDto {
  @IsString()
  @Length(2, 160)
  pattern!: string;

  @IsString()
  @Length(2, 40)
  category!: string;
}

export class AdminLoginDto {
  @IsString()
  @MaxLength(200)
  email!: string;

  @IsString()
  @Length(12, 200)
  password!: string;
}
