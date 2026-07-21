import {
  BadRequestException,
  Injectable,
  ServiceUnavailableException,
} from "@nestjs/common";
import { ConfigService } from "@nestjs/config";
import {
  DeleteObjectsCommand,
  GetObjectCommand,
  PutObjectCommand,
  S3Client,
} from "@aws-sdk/client-s3";
import { getSignedUrl } from "@aws-sdk/s3-request-presigner";
import { createHash, randomUUID } from "node:crypto";
import { connect } from "node:net";
import sharp from "sharp";
import { AuditService } from "../../common/audit.service";
import { PrismaService } from "../../common/prisma.service";

@Injectable()
export class MediaService {
  private readonly s3: S3Client;
  private readonly bucket: string;

  constructor(
    private readonly config: ConfigService,
    private readonly prisma: PrismaService,
    private readonly audit: AuditService,
  ) {
    this.bucket = config.get("MINIO_BUCKET") ?? "seychas-media";
    this.s3 = new S3Client({
      endpoint: `http://${config.get("MINIO_ENDPOINT") ?? "minio"}:${config.get("MINIO_PORT") ?? "9000"}`,
      region: "us-east-1",
      forcePathStyle: true,
      credentials: {
        accessKeyId: config.getOrThrow("MINIO_ACCESS_KEY"),
        secretAccessKey: config.getOrThrow("MINIO_SECRET_KEY"),
      },
    });
  }

  async uploadAvatar(userId: string, file?: Express.Multer.File) {
    if (!file?.buffer.length) throw new BadRequestException("Файл не передан");
    if (file.size > 5 * 1024 * 1024)
      throw new BadRequestException("Максимальный размер — 5 МБ");
    const format = this.magicFormat(file.buffer);
    if (!format)
      throw new BadRequestException("Разрешены только JPEG, PNG и WebP");
    await this.scan(file.buffer);

    let safe: Buffer;
    let thumbnail: Buffer;
    try {
      const pipeline = sharp(file.buffer, {
        failOn: "error",
        limitInputPixels: 24_000_000,
      }).rotate();
      const metadata = await pipeline.metadata();
      if (!["jpeg", "png", "webp"].includes(metadata.format ?? ""))
        throw new Error("Unsupported decoded format");
      safe = await pipeline
        .clone()
        .resize({
          width: 1600,
          height: 1600,
          fit: "inside",
          withoutEnlargement: true,
        })
        .webp({ quality: 86 })
        .toBuffer();
      thumbnail = await pipeline
        .clone()
        .resize(256, 256, { fit: "cover" })
        .webp({ quality: 80 })
        .toBuffer();
    } catch {
      throw new BadRequestException(
        "Изображение повреждено или имеет опасный формат",
      );
    }

    const id = randomUUID();
    const objectKey = `avatars/${userId}/${id}.webp`;
    const thumbnailKey = `avatars/${userId}/${id}.thumb.webp`;
    await Promise.all([
      this.s3.send(
        new PutObjectCommand({
          Bucket: this.bucket,
          Key: objectKey,
          Body: safe,
          ContentType: "image/webp",
          CacheControl: "private,max-age=3600",
          ServerSideEncryption: "AES256",
        }),
      ),
      this.s3.send(
        new PutObjectCommand({
          Bucket: this.bucket,
          Key: thumbnailKey,
          Body: thumbnail,
          ContentType: "image/webp",
          CacheControl: "private,max-age=3600",
          ServerSideEncryption: "AES256",
        }),
      ),
    ]);
    const previous = await this.prisma.userProfile.findUnique({
      where: { userId },
      select: { avatarMediaId: true },
    });
    const media = await this.prisma.mediaFile.create({
      data: {
        id,
        ownerId: userId,
        objectKey,
        thumbnailKey,
        mimeType: "image/webp",
        byteSize: safe.length,
        sha256: createHash("sha256").update(safe).digest("hex"),
        scanStatus: "clean",
      },
      select: { id: true, mimeType: true, byteSize: true },
    });
    await this.prisma.userProfile.update({
      where: { userId },
      data: { avatarMediaId: id },
    });
    if (previous?.avatarMediaId) {
      const old = await this.prisma.mediaFile.findFirst({
        where: { id: previous.avatarMediaId, ownerId: userId },
      });
      if (old)
        await this.deleteObjects(
          [old.objectKey, old.thumbnailKey].filter((key): key is string =>
            Boolean(key),
          ),
        );
      await this.prisma.mediaFile.deleteMany({
        where: { id: previous.avatarMediaId, ownerId: userId },
      });
    }
    await this.audit.write({
      actorUserId: userId,
      action: "media.avatar_uploaded",
      resourceType: "media_file",
      resourceId: id,
    });
    return media;
  }

  async signedUrl(userId: string, mediaId: string) {
    const media = await this.prisma.mediaFile.findFirst({
      where: { id: mediaId, ownerId: userId, scanStatus: "clean" },
    });
    if (!media) throw new BadRequestException("Media not found");
    const key = media.thumbnailKey ?? media.objectKey;
    return {
      url: await getSignedUrl(
        this.s3,
        new GetObjectCommand({ Bucket: this.bucket, Key: key }),
        { expiresIn: 300 },
      ),
      expiresIn: 300,
    };
  }

  async deleteAll(userId: string): Promise<void> {
    const media = await this.prisma.mediaFile.findMany({
      where: { ownerId: userId },
      select: { objectKey: true, thumbnailKey: true },
    });
    const keys = media
      .flatMap((item) => [item.objectKey, item.thumbnailKey])
      .filter((key): key is string => Boolean(key));
    await this.deleteObjects(keys);
  }

  private async deleteObjects(keys: string[]): Promise<void> {
    for (let offset = 0; offset < keys.length; offset += 1000) {
      await this.s3.send(
        new DeleteObjectsCommand({
          Bucket: this.bucket,
          Delete: {
            Quiet: true,
            Objects: keys.slice(offset, offset + 1000).map((Key) => ({ Key })),
          },
        }),
      );
    }
  }

  private magicFormat(buffer: Buffer): "jpeg" | "png" | "webp" | undefined {
    if (
      buffer.length >= 3 &&
      buffer[0] === 0xff &&
      buffer[1] === 0xd8 &&
      buffer[2] === 0xff
    )
      return "jpeg";
    if (
      buffer.length >= 8 &&
      buffer
        .subarray(0, 8)
        .equals(Buffer.from([137, 80, 78, 71, 13, 10, 26, 10]))
    )
      return "png";
    if (
      buffer.length >= 12 &&
      buffer.toString("ascii", 0, 4) === "RIFF" &&
      buffer.toString("ascii", 8, 12) === "WEBP"
    )
      return "webp";
    return undefined;
  }

  private async scan(buffer: Buffer): Promise<void> {
    try {
      const result = await new Promise<string>((resolve, reject) => {
        const socket = connect({
          host: this.config.get("CLAMAV_HOST") ?? "clamav",
          port: Number(this.config.get("CLAMAV_PORT") ?? 3310),
        });
        let response = "";
        socket.setTimeout(10_000);
        socket.once("connect", () => {
          socket.write("zINSTREAM\0");
          for (let offset = 0; offset < buffer.length; offset += 64 * 1024) {
            const chunk = buffer.subarray(offset, offset + 64 * 1024);
            const length = Buffer.alloc(4);
            length.writeUInt32BE(chunk.length);
            socket.write(length);
            socket.write(chunk);
          }
          socket.end(Buffer.alloc(4));
        });
        socket.on("data", (data) => {
          response += data.toString("utf8");
        });
        socket.once("end", () => resolve(response));
        socket.once("timeout", () => reject(new Error("Antivirus timeout")));
        socket.once("error", reject);
      });
      if (!result.includes("OK"))
        throw new BadRequestException("Файл не прошёл антивирусную проверку");
    } catch (error) {
      if (error instanceof BadRequestException) throw error;
      if (
        this.config.get("NODE_ENV") !== "production" &&
        this.config.get("ALLOW_UNSCANNED_UPLOADS") === "true"
      )
        return;
      throw new ServiceUnavailableException(
        "Антивирусная проверка временно недоступна",
      );
    }
  }
}
