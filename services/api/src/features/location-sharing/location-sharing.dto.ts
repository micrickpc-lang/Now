import { Type } from "class-transformer";
import {
  ArrayMaxSize,
  ArrayMinSize,
  IsArray,
  IsBoolean,
  IsIn,
  IsLatitude,
  IsLongitude,
  IsOptional,
  IsString,
  IsUUID,
  MaxLength,
} from "class-validator";

export const EXACT_LOCATION_AUDIENCES = [
  "SELECTED_FRIENDS",
  "CIRCLE",
  "ROOM",
] as const;

export const EXACT_LOCATION_EXPIRIES = [
  "THIRTY_MINUTES",
  "ONE_HOUR",
  "MEETING_END",
  "MANUAL",
] as const;

export class CreateExactLocationShareDto {
  @Type(() => Number)
  @IsLatitude()
  latitude!: number;

  @Type(() => Number)
  @IsLongitude()
  longitude!: number;

  @IsIn(EXACT_LOCATION_AUDIENCES)
  audience!: (typeof EXACT_LOCATION_AUDIENCES)[number];

  @IsIn(EXACT_LOCATION_EXPIRIES)
  expiryMode!: (typeof EXACT_LOCATION_EXPIRIES)[number];

  @IsBoolean()
  explicitConsent!: boolean;

  @IsBoolean()
  backgroundUpdatesEnabled!: boolean;

  @IsOptional()
  @IsArray()
  @ArrayMinSize(1)
  @ArrayMaxSize(50)
  @IsUUID("4", { each: true })
  recipientIds?: string[];

  @IsOptional()
  @IsUUID()
  circleId?: string;

  @IsOptional()
  @IsUUID()
  roomId?: string;

  @IsOptional()
  @IsString()
  @MaxLength(120)
  label?: string;
}

export class UpdateExactLocationShareDto {
  @Type(() => Number)
  @IsLatitude()
  latitude!: number;

  @Type(() => Number)
  @IsLongitude()
  longitude!: number;

  @IsOptional()
  @IsString()
  @MaxLength(120)
  label?: string;

  @IsOptional()
  @IsBoolean()
  backgroundUpdatesEnabled?: boolean;
}
