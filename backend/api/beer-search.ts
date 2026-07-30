import {
  BeerSearchError,
  parseSearchRequest,
  publicSearchResults,
  searchBeers
} from "../src/beer-search.js";

interface VercelRequest {
  method?: string;
  body?: unknown;
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

function sendError(response: VercelResponse, error: BeerSearchError): void {
  response.status(error.status).json({
    error: {
      code: error.code,
      message: error.message
    }
  });
}

export default async function handler(request: VercelRequest, response: VercelResponse): Promise<void> {
  response.setHeader("Cache-Control", "no-store, max-age=0");
  response.setHeader("CDN-Cache-Control", "no-store");
  response.setHeader("Vercel-CDN-Cache-Control", "no-store");
  response.setHeader("X-Content-Type-Options", "nosniff");

  if (request.method?.toUpperCase() !== "POST") {
    response.setHeader("Allow", "POST");
    sendError(response, new BeerSearchError(405, "method_not_allowed", "Use POST for beer search."));
    return;
  }

  const environment = runtimeEnvironment();
  const tavilyApiKey = environment.TAVILY_API_KEY?.trim() ?? "";
  const geminiApiKey = environment.GEMINI_API_KEY?.trim() ?? "";
  if (!tavilyApiKey || !geminiApiKey) {
    sendError(response, new BeerSearchError(503, "service_unconfigured", "Beer search is not configured."));
    return;
  }

  try {
    const parsed = parseSearchRequest(request.body);
    const results = await searchBeers(parsed, { tavilyApiKey, geminiApiKey });
    response.status(200).json({ results: publicSearchResults(results) });
  } catch (error) {
    if (error instanceof BeerSearchError) {
      sendError(response, error);
      return;
    }
    sendError(response, new BeerSearchError(500, "internal_error", "Beer search is temporarily unavailable."));
  }
}
