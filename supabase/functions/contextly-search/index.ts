import { createClient } from "jsr:@supabase/supabase-js@2";

type SearchRequest = {
  conversation_id: string;
  query: string;
  limit?: number;
};

type MessageRow = {
  id: string;
  conversation_id: string;
  sender_id: string;
  content: string;
  created_at: string;
};

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

Deno.serve(async (request) => {
  if (request.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  if (request.method !== "POST") {
    return jsonResponse({ error: "Method not allowed" }, 405);
  }

  try {
    const body = await request.json() as SearchRequest;
    const query = body.query?.trim();
    const limit = Math.min(Math.max(body.limit ?? 8, 1), 20);

    if (!body.conversation_id || !query) {
      return jsonResponse({ error: "conversation_id and query are required" }, 400);
    }

    const supabase = createClient(
      mustGetEnv("SUPABASE_URL"),
      mustGetEnv("SUPABASE_SERVICE_ROLE_KEY"),
    );

    const { data, error } = await supabase
      .from("contextly_messages")
      .select("id,conversation_id,sender_id,content,created_at")
      .eq("conversation_id", body.conversation_id)
      .order("created_at", { ascending: false })
      .limit(60);

    if (error) {
      throw error;
    }

    const queryEmbedding = await embed(query);
    const ranked = await Promise.all((data as MessageRow[]).map(async (message) => {
      const messageEmbedding = await embed(message.content);
      await supabase
        .from("contextly_messages")
        .update({ embedding: messageEmbedding })
        .eq("id", message.id);

      return {
        id: message.id,
        score: cosineSimilarity(queryEmbedding, messageEmbedding),
        message,
      };
    }));

    ranked.sort((left, right) => right.score - left.score);

    return jsonResponse(ranked.slice(0, limit));
  } catch (error) {
    const message = error instanceof Error ? error.message : "Unknown error";
    return jsonResponse({ error: message }, 500);
  }
});

async function embed(text: string): Promise<number[]> {
  const apiKey = mustGetEnv("OPENAI_API_KEY");
  const model = Deno.env.get("EMBEDDING_MODEL") ?? "text-embedding-3-small";

  const response = await fetch("https://api.openai.com/v1/embeddings", {
    method: "POST",
    headers: {
      "Authorization": `Bearer ${apiKey}`,
      "Content-Type": "application/json",
    },
    body: JSON.stringify({ model, input: text }),
  });

  if (!response.ok) {
    throw new Error(`Embedding request failed: ${response.status} ${await response.text()}`);
  }

  const payload = await response.json();
  return payload.data[0].embedding;
}

function cosineSimilarity(left: number[], right: number[]): number {
  let dot = 0;
  let leftMagnitude = 0;
  let rightMagnitude = 0;

  for (let index = 0; index < left.length; index += 1) {
    dot += left[index] * right[index];
    leftMagnitude += left[index] * left[index];
    rightMagnitude += right[index] * right[index];
  }

  return dot / (Math.sqrt(leftMagnitude) * Math.sqrt(rightMagnitude));
}

function mustGetEnv(name: string): string {
  const value = Deno.env.get(name);
  if (!value) {
    throw new Error(`Missing required environment variable: ${name}`);
  }
  return value;
}

function jsonResponse(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: {
      ...corsHeaders,
      "Content-Type": "application/json",
    },
  });
}
