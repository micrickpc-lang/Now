import { BadRequestException, Injectable } from "@nestjs/common";
import { PrismaService } from "./prisma.service";

const phonePattern = /(?:\+?\d[\s()-]*){8,}/u;
const urlPattern =
  /https?:\/\/|(?:^|\s)(?:www\.)?[^\s]+\.(?:ru|com|net|org)(?:\/|\s|$)/iu;

@Injectable()
export class ContentPolicyService {
  constructor(private readonly prisma: PrismaService) {}

  async assertAllowed(text: string, limitedMode = false): Promise<void> {
    if (limitedMode && (phonePattern.test(text) || urlPattern.test(text))) {
      throw new BadRequestException(
        "Контактные данные и ссылки здесь недоступны",
      );
    }
    const patterns = await this.prisma.forbiddenWord.findMany({
      where: { active: true },
    });
    const normalized = text.toLocaleLowerCase("ru-RU");
    if (
      patterns.some(({ pattern }) =>
        normalized.includes(pattern.toLocaleLowerCase("ru-RU")),
      )
    ) {
      throw new BadRequestException("Текст нарушает правила сообщества");
    }
  }
}
