import { ConfigService } from "@nestjs/config";
import { SmsRuOtpProvider } from "./otp.provider";

function config(values: Record<string, string>) {
  return {
    get: jest.fn((key: string) => values[key]),
    getOrThrow: jest.fn((key: string) => {
      const value = values[key];
      if (value === undefined) throw new Error(`Missing ${key}`);
      return value;
    }),
  } as unknown as ConfigService;
}

describe("SmsRuOtpProvider", () => {
  afterEach(() => {
    jest.restoreAllMocks();
  });

  it("submits an OTP without placing credentials in the URL", async () => {
    const fetchMock = jest.spyOn(global, "fetch").mockResolvedValue({
      ok: true,
      json: async () => ({
        status: "OK",
        status_code: 100,
        sms: {
          "15555550123": { status: "OK", status_code: 100 },
        },
      }),
    } as Response);
    const provider = new SmsRuOtpProvider(
      config({
        APP_ENV: "staging",
        SMS_RU_API_ID: "unit-test-provider-credential",
        SMS_RU_TIMEOUT_MS: "1000",
        OTP_TTL_SECONDS: "300",
      }),
    );

    await provider.send("+15555550123", "654321", {
      requestIp: "192.0.2.10",
    });

    expect(fetchMock).toHaveBeenCalledTimes(1);
    const [url, options] = fetchMock.mock.calls[0]!;
    expect(url).toBe("https://sms.ru/sms/send");
    expect(String(url)).not.toContain("unit-test-provider-credential");
    expect(options?.method).toBe("POST");
    const body = new URLSearchParams(String(options?.body));
    expect(body.get("to")).toBe("15555550123");
    expect(body.get("api_id")).toBe("unit-test-provider-credential");
    expect(body.get("msg")).toContain("654321");
    expect(body.get("ip")).toBe("192.0.2.10");
  });

  it("does not call the external provider for allowlisted staging tests", async () => {
    const fetchMock = jest.spyOn(global, "fetch");
    const provider = new SmsRuOtpProvider(
      config({
        APP_ENV: "staging",
        STAGING_TEST_PHONE_ALLOWLIST: "+15555550123",
        SMS_RU_API_ID: "unit-test-provider-credential",
      }),
    );

    await provider.send("+15555550123", "654321", {
      requestIp: "192.0.2.10",
    });

    expect(fetchMock).not.toHaveBeenCalled();
  });

  it("fails closed when the provider rejects a message", async () => {
    jest.spyOn(global, "fetch").mockResolvedValue({
      ok: true,
      json: async () => ({
        status: "ERROR",
        status_code: 200,
      }),
    } as Response);
    const provider = new SmsRuOtpProvider(
      config({
        APP_ENV: "production",
        SMS_RU_API_ID: "unit-test-provider-credential",
        SMS_RU_TIMEOUT_MS: "1000",
      }),
    );

    await expect(
      provider.send("+15555550123", "654321", {
        requestIp: "192.0.2.10",
      }),
    ).rejects.toThrow("SMS provider rejected");
  });
});
