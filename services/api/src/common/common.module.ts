import { Global, Module } from "@nestjs/common";
import { CryptoService } from "./crypto.service";
import { PrismaService } from "./prisma.service";
import { AuditService } from "./audit.service";

@Global()
@Module({
  providers: [PrismaService, CryptoService, AuditService],
  exports: [PrismaService, CryptoService, AuditService],
})
export class CommonModule {}
