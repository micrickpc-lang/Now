import { Type } from "class-transformer";
import { IsLatitude, IsLongitude, IsString, Length } from "class-validator";

export class MapSearchDto {
  @IsString()
  @Length(2, 120)
  q!: string;
}

export class ApproximateLocationDto {
  @Type(() => Number)
  @IsLatitude()
  latitude!: number;

  @Type(() => Number)
  @IsLongitude()
  longitude!: number;
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
