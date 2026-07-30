export interface HealthPayload {
  status: "ok";
  contract: "tavily-gemini-v1";
  providers: {
    tavily: boolean;
    gemini: boolean;
  };
}

export function healthPayload(environment: Record<string, string | undefined>): HealthPayload {
  return {
    status: "ok",
    contract: "tavily-gemini-v1",
    providers: {
      tavily: Boolean(environment.TAVILY_API_KEY?.trim()),
      gemini: Boolean(environment.GEMINI_API_KEY?.trim())
    }
  };
}
