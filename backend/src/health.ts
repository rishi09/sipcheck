export interface HealthPayload {
  status: "ok";
  providers: {
    tavily: boolean;
    gemini: boolean;
  };
}

export function healthPayload(environment: Record<string, string | undefined>): HealthPayload {
  return {
    status: "ok",
    providers: {
      tavily: Boolean(environment.TAVILY_API_KEY?.trim()),
      gemini: Boolean(environment.GEMINI_API_KEY?.trim())
    }
  };
}
