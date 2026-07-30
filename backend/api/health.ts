import { healthPayload } from "../src/health.js";

interface VercelRequest {
  method?: string;
}

interface VercelResponse {
  setHeader(name: string, value: string): void;
  status(code: number): VercelResponse;
  json(value: unknown): void;
}

function runtimeEnvironment(): Record<string, string | undefined> {
  const runtime = globalThis as typeof globalThis & {
    process?: { env?: Record<string, string | undefined> };
  };
  return runtime.process?.env ?? {};
}

export default function handler(request: VercelRequest, response: VercelResponse): void {
  response.setHeader("Cache-Control", "no-store, max-age=0");
  response.setHeader("CDN-Cache-Control", "no-store");
  response.setHeader("Vercel-CDN-Cache-Control", "no-store");
  response.setHeader("X-Content-Type-Options", "nosniff");

  if (request.method?.toUpperCase() !== "GET") {
    response.setHeader("Allow", "GET");
    response.status(405).json({
      error: {
        code: "method_not_allowed",
        message: "Use GET for health checks."
      }
    });
    return;
  }

  response.status(200).json(healthPayload(runtimeEnvironment()));
}
