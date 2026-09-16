create extension if not exists vector with schema extensions;

create table if not exists public.contextly_users (
    id uuid primary key default gen_random_uuid(),
    username text not null unique,
    display_name text not null,
    created_at timestamptz not null default now()
);

create table if not exists public.contextly_conversations (
    id uuid primary key default gen_random_uuid(),
    name text,
    created_at timestamptz not null default now()
);

create table if not exists public.contextly_conversation_members (
    conversation_id uuid not null references public.contextly_conversations(id) on delete cascade,
    user_id uuid not null references public.contextly_users(id) on delete cascade,
    joined_at timestamptz not null default now(),
    primary key (conversation_id, user_id)
);

create table if not exists public.contextly_messages (
    id uuid primary key default gen_random_uuid(),
    conversation_id uuid not null references public.contextly_conversations(id) on delete cascade,
    sender_id uuid not null references public.contextly_users(id) on delete restrict,
    content text not null check (length(trim(content)) > 0),
    embedding vector(1536),
    created_at timestamptz not null default now()
);

create index if not exists contextly_messages_conversation_created_idx
    on public.contextly_messages (conversation_id, created_at);

create index if not exists contextly_messages_embedding_idx
    on public.contextly_messages
    using hnsw (embedding vector_cosine_ops)
    where embedding is not null;

alter table public.contextly_users enable row level security;
alter table public.contextly_conversations enable row level security;
alter table public.contextly_conversation_members enable row level security;
alter table public.contextly_messages enable row level security;

drop policy if exists "contextly users are readable" on public.contextly_users;
create policy "contextly users are readable"
on public.contextly_users
for select
to anon, authenticated
using (true);

drop policy if exists "contextly conversations are readable" on public.contextly_conversations;
create policy "contextly conversations are readable"
on public.contextly_conversations
for select
to anon, authenticated
using (true);

drop policy if exists "contextly members are readable" on public.contextly_conversation_members;
create policy "contextly members are readable"
on public.contextly_conversation_members
for select
to anon, authenticated
using (true);

drop policy if exists "contextly messages are readable" on public.contextly_messages;
create policy "contextly messages are readable"
on public.contextly_messages
for select
to anon, authenticated
using (true);

drop policy if exists "contextly demo senders can create messages" on public.contextly_messages;
create policy "contextly demo senders can create messages"
on public.contextly_messages
for insert
to anon, authenticated
with check (
    exists (
        select 1
        from public.contextly_conversation_members member
        where member.conversation_id = contextly_messages.conversation_id
          and member.user_id = contextly_messages.sender_id
    )
);

grant select on public.contextly_users to anon, authenticated;
grant select on public.contextly_conversations to anon, authenticated;
grant select on public.contextly_conversation_members to anon, authenticated;
grant select, insert on public.contextly_messages to anon, authenticated;

create or replace function public.match_contextly_messages(
    query_embedding vector(1536),
    match_conversation_id uuid,
    match_count int default 8
)
returns table (
    id uuid,
    conversation_id uuid,
    sender_id uuid,
    content text,
    created_at timestamptz,
    score double precision
)
language sql
stable
set search_path = public, extensions
as $$
    select
        message.id,
        message.conversation_id,
        message.sender_id,
        message.content,
        message.created_at,
        1 - (message.embedding <=> query_embedding) as score
    from public.contextly_messages message
    where message.conversation_id = match_conversation_id
      and message.embedding is not null
    order by message.embedding <=> query_embedding
    limit least(match_count, 20);
$$;

grant execute on function public.match_contextly_messages(vector, uuid, int) to authenticated, service_role;

insert into public.contextly_users (id, username, display_name)
values
    ('11111111-1111-1111-1111-111111111111', 'nathan', 'Nathan'),
    ('22222222-2222-2222-2222-222222222222', 'kevin', 'Kevin'),
    ('33333333-3333-3333-3333-333333333333', 'maya', 'Maya')
on conflict (id) do update
set username = excluded.username,
    display_name = excluded.display_name;

insert into public.contextly_conversations (id, name)
values ('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', 'Contextly MVP')
on conflict (id) do update
set name = excluded.name;

insert into public.contextly_conversation_members (conversation_id, user_id)
values
    ('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', '11111111-1111-1111-1111-111111111111'),
    ('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', '22222222-2222-2222-2222-222222222222'),
    ('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', '33333333-3333-3333-3333-333333333333')
on conflict do nothing;

insert into public.contextly_messages (id, conversation_id, sender_id, content)
values
    (
        'aaaaaaaa-0000-0000-0000-000000000001',
        'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa',
        '11111111-1111-1111-1111-111111111111',
        'Let''s meet at Klaus at 5 tomorrow.'
    ),
    (
        'aaaaaaaa-0000-0000-0000-000000000002',
        'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa',
        '22222222-2222-2222-2222-222222222222',
        'I''ll finish the backend before then.'
    ),
    (
        'aaaaaaaa-0000-0000-0000-000000000003',
        'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa',
        '33333333-3333-3333-3333-333333333333',
        'I can work on the database after class.'
    )
on conflict (id) do nothing;
