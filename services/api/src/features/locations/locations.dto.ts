import { Type } from "class-transformer";
import {
  ArrayMaxSize,
  ArrayMinSize,
  IsArray,
  IsBoolean,
  IsDateString,
  IsEnum,
  IsLatitude,
  IsLongitude,
  IsOptional,
  IsUUID,
  Max,
  Min,
  ValidateIf,
} from "class-validator";

export enum LocationShareAudienceDto {
  FRIENDS = "FRIENDS",
  SELECTED = "SELECTED",
}

export enum LocationSharePrecisionDto {
  APPROXIMATE = "APPROXIMATE",
  EXACT = "EXACT",
}

export class UpdateMyLocationDto {
  @Type(() => Number)
  @IsLatitude()
  latitude!: number;

  @Type(() => Number)
  @IsLongitude()
  longitude!: number;

  @IsOptional()
  @IsDateString()
  capturedAt?: string;
}

export class CreateGlobalLocationShareDto {
  @IsEnum(LocationShareAudienceDto)
  audience!: LocationShareAudienceDto;

  @ValidateIf(
    (value: CreateGlobalLocationShareDto) =>
      value.audience === LocationShareAudienceDto.SELECTED,
  )
  @IsArray()
  @ArrayMinSize(1)
  @ArrayMaxSize(100)
  @IsUUID("4", { each: true })
  recipientIds?: string[];

  @IsEnum(LocationSharePrecisionDto)
  precision!: LocationSharePrecisionDto;

  @Type(() => Number)
  @Min(5)
  @Max(1440)
  ttlMinutes!: number;

  @IsBoolean()
  explicitConsent!: boolean;
}
