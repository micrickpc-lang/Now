import "reflect-metadata";
import { RequestMethod, ValidationPipe } from "@nestjs/common";
import { ConfigService } from "@nestjs/config";
import { NestFactory } from "@nestjs/core";
import type { NestExpressApplication } from "@nestjs/platform-express";
import { DocumentBuilder, SwaggerModule } from "@nestjs/swagger";
import cookieParser from "cookie-parser";
import helmet from "helmet";
import { AppModule } from "./app.module";
import { JsonLogger } from "./json-logger";

async function bootstrap() {
  const app = await NestFactory.create<NestExpressApplication>(AppModule, {
    logger: new JsonLogger(),
    bodyParser: true,
  });
  const config = app.get(ConfigService);
  const production = config.get("NODE_ENV") === "production";
  const trustProxyHops = Number(config.get("TRUST_PROXY_HOPS") ?? 0);
  if (trustProxyHops > 0) app.set("trust proxy", trustProxyHops);
  app.setGlobalPrefix("api/v1", {
    exclude: [
      { path: "health", method: RequestMethod.GET },
      { path: "ready", method: RequestMethod.GET },
      { path: "metrics", method: RequestMethod.GET },
    ],
  });
  app.use(
    helmet({
      strictTransportSecurity: production
        ? { maxAge: 31_536_000, includeSubDomains: true, preload: true }
        : false,
      contentSecurityPolicy: {
        directives: {
          defaultSrc: ["'none'"],
          frameAncestors: ["'none'"],
          baseUri: ["'none'"],
        },
      },
    }),
  );
  app.use(cookieParser());
  const allowedOrigins = (config.get<string>("APP_ORIGINS") ?? "")
    .split(",")
    .map((value) => value.trim())
    .filter(Boolean);
  app.enableCors({
    origin: (
      origin: string | undefined,
      callback: (error: Error | null, allow?: boolean) => void,
    ) => callback(null, !origin || allowedOrigins.includes(origin)),
    methods: ["GET", "POST", "PATCH", "DELETE"],
    allowedHeaders: [
      "Authorization",
      "Content-Type",
      "Idempotency-Key",
      "X-CSRF-Token",
    ],
    credentials: true,
    maxAge: 600,
  });
  app.useGlobalPipes(
    new ValidationPipe({
      whitelist: true,
      forbidNonWhitelisted: true,
      transform: true,
      transformOptions: { enableImplicitConversion: false },
    }),
  );
  app.enableShutdownHooks();

  const swagger = new DocumentBuilder()
    .setTitle("Сейчас API")
    .setDescription("Versioned private social coordination API")
    .setVersion("1.0")
    .addBearerAuth()
    .build();
  SwaggerModule.setup("docs", app, SwaggerModule.createDocument(app, swagger), {
    customSiteTitle: "Сейчас API",
    swaggerOptions: { persistAuthorization: false },
  });

  await app.listen(Number(config.get("PORT") ?? 3000), "0.0.0.0");
}

void bootstrap();
