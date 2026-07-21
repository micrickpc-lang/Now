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
import { Public } from "../../common/http";
import { ApproximateLocationDto } from "./maps.dto";
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
  search(@Query("q") query: string) {
    return this.maps.search(query ?? "");
  }

  @Get("reverse")
  reverse(@Query("lat") lat: string, @Query("lon") lon: string) {
    return this.maps.reverse(Number(lat), Number(lon));
  }

  @Post("approximate-location")
  approximate(@Body() dto: ApproximateLocationDto) {
    return this.maps.approximate(dto.latitude, dto.longitude);
  }
}
