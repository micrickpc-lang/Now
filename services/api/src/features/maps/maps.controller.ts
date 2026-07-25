import {
  Body,
  Controller,
  Get,
  Header,
  Param,
  Post,
  Query,
  Res,
} from "@nestjs/common";
import { ApiBearerAuth, ApiTags } from "@nestjs/swagger";
import type { Response } from "express";
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
  style() {
    return this.maps.style();
  }

  @Get("tilejson.json")
  @Public()
  tileJson() {
    return this.maps.tileJson();
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
  search(@Query() query: MapSearchDto) {
    return this.maps.search(query.q);
  }

  @Get("reverse")
  reverse(@Query() query: ReverseLocationDto) {
    return this.maps.reverse(query.lat, query.lon);
  }

  @Post("approximate-location")
  approximate(
    @CurrentAuth() auth: { userId: string },
    @Body() dto: ApproximateLocationDto,
  ) {
    return this.maps.createSafeLocation(auth.userId, dto);
  }
}
