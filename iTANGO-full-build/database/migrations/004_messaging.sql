-- =============================================================================
-- Migration 004: Messaging (DMs, Groups, Event Rooms)
-- =============================================================================

create table conversations (
    id uuid primary key default uuid_generate_v4(),
    type conversation_type not null,
    event_id uuid references events(id) on delete cascade, -- set only when type = 'event_room'
    title text, -- used for groups; event rooms derive title from events.title
    created_by uuid references profiles(id),
    created_at timestamptz not null default now(),

    constraint event_room_has_event check (
        (type = 'event_room' and event_id is not null) or (type <> 'event_room')
    )
);
create unique index idx_conversations_event_room on conversations (event_id) where type = 'event_room';
create index idx_conversations_type on conversations (type);

create table conversation_participants (
    conversation_id uuid not null references conversations(id) on delete cascade,
    user_id uuid not null references profiles(id) on delete cascade,
    joined_at timestamptz not null default now(),
    last_read_at timestamptz,
    is_muted boolean not null default false,
    primary key (conversation_id, user_id)
);
create index idx_conversation_participants_user on conversation_participants (user_id);

create table messages (
    id uuid primary key default uuid_generate_v4(),
    conversation_id uuid not null references conversations(id) on delete cascade,
    sender_id uuid references profiles(id) on delete set null, -- null = system message
    message_type message_type not null default 'text',
    content text,
    media_url text,
    reply_to_id uuid references messages(id) on delete set null,
    is_pinned boolean not null default false,
    expires_at timestamptz, -- disappearing messages
    created_at timestamptz not null default now(),
    edited_at timestamptz,
    deleted_at timestamptz -- soft delete, preserves moderation trail
);
create index idx_messages_conversation_created on messages (conversation_id, created_at desc);
create index idx_messages_reply_to on messages (reply_to_id);

create table message_reactions (
    message_id uuid not null references messages(id) on delete cascade,
    user_id uuid not null references profiles(id) on delete cascade,
    emoji text not null,
    created_at timestamptz not null default now(),
    primary key (message_id, user_id, emoji)
);

-- -----------------------------------------------------------------------------
-- Room engagement snapshots — periodically written FROM Redis, not computed
-- live from `messages` on every read. See design-decisions doc §2.
-- -----------------------------------------------------------------------------
create table room_engagement_snapshots (
    conversation_id uuid not null references conversations(id) on delete cascade,
    window_start timestamptz not null,
    message_count integer not null default 0,
    reaction_count integer not null default 0,
    temperature room_temperature not null default 'cold',
    primary key (conversation_id, window_start)
);
create index idx_room_engagement_latest on room_engagement_snapshots (conversation_id, window_start desc);

-- -----------------------------------------------------------------------------
-- Check-in → event room auto-join (completes the deferred trigger from
-- migration 003: `on_check_in`)
-- -----------------------------------------------------------------------------
create or replace function join_event_room_on_checkin()
returns trigger as $$
declare
    v_conversation_id uuid;
begin
    select id into v_conversation_id from conversations
        where event_id = new.event_id and type = 'event_room';

    if v_conversation_id is null then
        insert into conversations (type, event_id, title)
        values ('event_room', new.event_id, (select title from events where id = new.event_id))
        returning id into v_conversation_id;
    end if;

    insert into conversation_participants (conversation_id, user_id)
    values (v_conversation_id, new.user_id)
    on conflict (conversation_id, user_id) do nothing;

    return new;
end;
$$ language plpgsql;

create trigger trg_join_event_room_on_checkin after insert on check_ins
    for each row execute function join_event_room_on_checkin();
