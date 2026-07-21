import {
  IsBoolean,
  IsObject,
  IsOptional,
  IsString,
  Length,
  MaxLength,
} from "class-validator";

export class UpdateUserDto {
  @IsOptional()
  @IsString()
  @Length(2, 40)
  displayName?: string;

  @IsOptional()
  @IsString()
  @MaxLength(16)
  emoji?: string;

  @IsOptional()
  @IsString()
  @MaxLength(160)
  bio?: string;
}

export class UpdatePrivacyDto {
  @IsOptional()
  @IsBoolean()
  showRecentActivity?: boolean;

  @IsObject()
  settings!: Record<string, boolean | string>;
}

export class DeleteAccountDto {
  @IsString()
  @Length(6, 64)
  confirmation!: string;
}
