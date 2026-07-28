import {
  BadRequestException,
  Body,
  Controller,
  Get,
  Header,
  Param,
  Post,
  Query,
  Req,
  Res,
} from "@nestjs/common";
import { ApiBearerAuth, ApiTags } from "@nestjs/swagger";
import { Throttle } from "@nestjs/throttler";
import type { Request, Response } from "express";
import { CurrentAuth, Public } from "../../common/http";
import {
  ApproximateLocationDto,
  MapSearchDto,
  ReverseLocationDto,
} from "./maps.dto";
import { MapsService } from "./maps.service";

@ApiTags("maps")
@ApiBearerAuth()
@Controller("maps")
export class MapsController {
  constructor(private readonly maps: MapsService) {}

  @Get("style.json")
  @Public()
  style(@Req() request: Request) {
    return this.maps.style(this.requestMapBaseUrl(request));
  }

  @Get("tilejson.json")
  @Public()
  tileJson(@Req() request: Request) {
    return this.maps.tileJson(this.requestMapBaseUrl(request));
  }

  @Get("tiles/:z/:x/:y")
  @Public()
  @Header("Cache-Control", "public, max-age=86400, immutable")
  async tile(
    @Param("z") z: string,
    @Param("x") x: string,
    @Param("y") y: string,
    @Res() response: Response,
  ) {
    const tile = await this.maps.tile(
      Number(z),
      Number(x),
      Number(y.replace(/\.pbf$/u, "")),
    );
    response.type(tile.contentType).send(Buffer.from(tile.body));
  }

  @Get("search")
  @Throttle({ default: { limit: 30, ttl: 60_000 } })
  search(@Query() query: MapSearchDto) {
    return this.maps.search(query.q);
  }

  @Get("reverse")
  @Throttle({ default: { limit: 30, ttl: 60_000 } })
  reverse(@Query() query: ReverseLocationDto) {
    if (query.lon === undefined && query.lng === undefined) {
      throw new BadRequestException("Either lon or lng is required");
    }
    if (
      query.lon !== undefined &&
      query.lng !== undefined &&
      query.lon !== query.lng
    ) {
      throw new BadRequestException("lon and lng must match when both are set");
    }
    return this.maps.reverse(query.lat, query.lon ?? query.lng!);
  }

  @Post("approximate-location")
  approximate(
    @CurrentAuth() auth: { userId: string },
    @Body() dto: ApproximateLocationDto,
  ) {
    return this.maps.createSafeLocation(auth.userId, dto);
  }

  private requestMapBaseUrl(request: Request): string | undefined {
    const host = request.get("host");
    if (!host) return undefined;

    try {
      const origin = new URL(`${request.protocol}://${host}`);
      if (
        origin.username ||
        origin.password ||
        origin.pathname !== "/" ||
        origin.search ||
        origin.hash
      ) {
        return undefined;
      }
      return `${origin.origin}/api/v1/maps`;
    } catch {
      return undefined;
    }
  }
}
