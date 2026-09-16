# Contextly

A SwiftUI iOS app for semantic message search across conversations. Instead of relying on exact keyword matching, Contextly uses vector embeddings to let you find messages by meaning — ask natural questions and get contextually relevant results.

## Features

- **Conversation browser** — view multiple group and direct message threads
- **Real-time messaging** — send messages and see them appear instantly
- **Semantic search** — search conversation history using natural language via AI-powered vector similarity
- **Demo mode** — works fully offline with realistic sample data; no Supabase setup required to run

## Tech Stack

| Layer | Technology |
|---|---|
| iOS App | SwiftUI |
| Backend | [Supabase](https://supabase.com) (Postgres + Edge Functions) |
| Vector Search | `pgvector` with HNSW index (1536-dimension embeddings) |
| Embeddings | OpenAI `text-embedding-ada-002` (via Supabase Edge Function) |

## Project Structure

```
Contextly/
├── Contextly/
│   ├── ContextlyApp.swift        # App entry point
│   ├── ContentView.swift         # Main UI (conversation list, chat, search)
│   ├── ContextlyModels.swift     # Data models + demo data
│   └── SupabaseService.swift     # Supabase REST + Edge Function client
└── supabase/
    ├── contextly_mvp.sql         # Database schema, RLS policies, seed data
    └── functions/                # Supabase Edge Functions (search handler)
```

## Getting Started

### Demo Mode (no backend needed)

Open `Contextly.xcodeproj` in Xcode and run the app. It will launch in demo mode with pre-seeded conversations and messages. Semantic search works locally using keyword heuristics.

### With Supabase (full AI search)

1. **Create a Supabase project** at [supabase.com](https://supabase.com)

2. **Run the schema** — paste the contents of `supabase/contextly_mvp.sql` into the Supabase SQL editor and execute it. This creates the tables, enables `pgvector`, sets up RLS policies, and seeds sample data.

3. **Deploy the Edge Function** — from your project root:
   ```bash
   supabase functions deploy contextly-search
   ```

4. **Configure the app** — in the app's settings sheet, enter your:
   - Supabase project URL (e.g. `https://xxxx.supabase.co`)
   - Supabase publishable (anon) key

   The app switches out of demo mode automatically once valid credentials are provided.

## Database Schema

| Table | Description |
|---|---|
| `contextly_users` | User profiles (id, username, display name) |
| `contextly_conversations` | Conversation threads |
| `contextly_conversation_members` | Many-to-many conversation membership |
| `contextly_messages` | Messages with optional `vector(1536)` embedding column |

Row Level Security is enabled on all tables. The `match_contextly_messages` SQL function performs cosine-similarity search using the HNSW index.

## Requirements

- Xcode 16+
- iOS 17+
- Swift 6
