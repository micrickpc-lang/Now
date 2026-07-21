import { Type } from "class-transformer";
import {
  ArrayMaxSize,
  ArrayMinSize,
  IsArray,
  IsBoolean,
  IsDateString,
  IsIn,
  IsLatitude,
  IsLongitude,
  IsOptional,
  IsString,
  IsUUID,
  Length,
  Max,
  MaxLength,
  Min,
} from "class-validator";

export class CreateMessageDto {
  @IsString()
  @Length(1, 1000)
  body!: string;
}

export const ROOM_REACTIONS = ["👍", "❤️", "😂", "😮", "😢", "🎉"] as const;

export class ReactionDto {
  @IsIn(ROOM_REACTIONS)
  emoji!: (typeof ROOM_REACTIONS)[number];
}

export class CreatePollDto {
  @IsString()
  @Length(1, 200)
  question!: string;

  @IsArray()
  @ArrayMinSize(2)
  @ArrayMaxSize(8)
  @IsString({ each: true })
  options!: string[];

  @IsOptional()
  @IsDateString()
  closesAt?: string;
}

export class VoteDto {
  @IsUUID()
  optionId!: string;
}

export class ShareLocationDto {
  @Type(() => Number)
  @IsLatitude()
  latitude!: number;

  @Type(() => Number)
  @IsLongitude()
  longitude!: number;

  @Type(() => Number)
  @Min(5)
  @Max(180)
  ttlMinutes!: number;

  @IsBoolean()
  explicitConsent!: boolean;

  @IsOptional()
  @IsString()
  @MaxLength(120)
  label?: string;
}
