import { Type } from "class-transformer";
import {
  IsIn,
  IsLatitude,
  IsLongitude,
  IsNumber,
  IsString,
  Length,
  Max,
  Min,
} from "class-validator";

export class MapSearchDto {
  @IsString()
  @Length(2, 120)
  q!: string;
}

export class ReverseLocationDto {
  @Type(() => Number)
  @IsLatitude()
  lat!: number;

  @Type(() => Number)
  @IsLongitude()
  lon!: number;
}

export class ApproximateLocationDto {
  @IsIn(["CITY", "DISTRICT", "APPROXIMATE"])
  mode!: "CITY" | "DISTRICT" | "APPROXIMATE";

  @Type(() => Number)
  @IsLatitude()
  latitude!: number;

  @Type(() => Number)
  @IsLongitude()
  longitude!: number;

  @Type(() => Number)
  @IsNumber({ allowInfinity: false, allowNaN: false })
  @Min(0)
  @Max(100_000)
  accuracyMeters!: number;
}

export interface RoutingProvider {
  route(
    points: Array<{ latitude: number; longitude: number }>,
  ): Promise<unknown>;
}

export class DisabledRoutingProvider implements RoutingProvider {
  route(): Promise<never> {
    return Promise.reject(new Error("Routing is disabled in MVP"));
  }
}
