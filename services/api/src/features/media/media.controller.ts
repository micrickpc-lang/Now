import {
  Controller,
  Get,
  Param,
  Post,
  UploadedFile,
  UseInterceptors,
} from "@nestjs/common";
import { FileInterceptor } from "@nestjs/platform-express";
import { ApiBearerAuth, ApiConsumes, ApiTags } from "@nestjs/swagger";
import { CurrentAuth } from "../../common/http";
import { MediaService } from "./media.service";

@ApiTags("media")
@ApiBearerAuth()
@Controller()
export class MediaController {
  constructor(private readonly media: MediaService) {}

  @Post("users/me/avatar")
  @ApiConsumes("multipart/form-data")
  @UseInterceptors(
    FileInterceptor("file", {
      limits: { fileSize: 5 * 1024 * 1024, files: 1, fields: 0 },
    }),
  )
  avatar(
    @CurrentAuth() auth: { userId: string },
    @UploadedFile() file?: Express.Multer.File,
  ) {
    return this.media.uploadAvatar(auth.userId, file);
  }

  @Get("media/:id/url")
  url(@CurrentAuth() auth: { userId: string }, @Param("id") id: string) {
    return this.media.signedUrl(auth.userId, id);
  }
}
