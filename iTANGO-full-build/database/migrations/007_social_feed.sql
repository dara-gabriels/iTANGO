-- =============================================================================
-- Migration 007: Social Feed (Posts, Stories)
-- =============================================================================

create table posts (
    id uuid primary key default uuid_generate_v4(),
    user_id uuid not null references profiles(id) on delete cascade,
    event_id uuid references events(id) on delete set null, -- tags a post to a live event
    caption text,
    media_urls text[] not null default '{}',
    location geography(Point, 4326),
    like_count integer not null default 0,   -- denormalized, trigger-maintained
    comment_count integer not null default 0,
    created_at timestamptz not null default now(),
    deleted_at timestamptz
);
create index idx_posts_created on posts (created_at desc) where deleted_at is null;
create index idx_posts_event on posts (event_id, created_at desc) where deleted_at is null;
create index idx_posts_user on posts (user_id, created_at desc);

create table post_likes (
    post_id uuid not null references posts(id) on delete cascade,
    user_id uuid not null references profiles(id) on delete cascade,
    created_at timestamptz not null default now(),
    primary key (post_id, user_id)
);

create table post_comments (
    id uuid primary key default uuid_generate_v4(),
    post_id uuid not null references posts(id) on delete cascade,
    user_id uuid not null references profiles(id) on delete cascade,
    content text not null,
    created_at timestamptz not null default now(),
    deleted_at timestamptz
);
create index idx_post_comments_post on post_comments (post_id, created_at);

create table post_bookmarks (
    post_id uuid not null references posts(id) on delete cascade,
    user_id uuid not null references profiles(id) on delete cascade,
    created_at timestamptz not null default now(),
    primary key (post_id, user_id)
);

create or replace function bump_post_like_count()
returns trigger as $$
begin
    if tg_op = 'INSERT' then
        update posts set like_count = like_count + 1 where id = new.post_id;
    elsif tg_op = 'DELETE' then
        update posts set like_count = like_count - 1 where id = old.post_id;
    end if;
    return null;
end;
$$ language plpgsql;
create trigger trg_post_likes_count after insert or delete on post_likes
    for each row execute function bump_post_like_count();

create or replace function bump_post_comment_count()
returns trigger as $$
begin
    update posts set comment_count = comment_count + 1 where id = new.post_id;
    return new;
end;
$$ language plpgsql;
create trigger trg_post_comments_count after insert on post_comments
    for each row execute function bump_post_comment_count();

-- -----------------------------------------------------------------------------
-- Stories — 24h ephemeral content. expires_at enforced via a scheduled
-- cleanup job (pg_cron) that hard-deletes rows past expiry; the app also
-- filters `where expires_at > now()` defensively.
-- -----------------------------------------------------------------------------
create table stories (
    id uuid primary key default uuid_generate_v4(),
    user_id uuid not null references profiles(id) on delete cascade,
    media_url text not null,
    media_type text not null default 'image', -- 'image' | 'video'
    caption text,
    music_track text,
    location geography(Point, 4326),
    is_highlight boolean not null default false,
    highlight_collection text, -- e.g. "Neon Nights", "VIP Life" — groups stories into a Highlights reel
    created_at timestamptz not null default now(),
    expires_at timestamptz not null default (now() + interval '24 hours')
);
create index idx_stories_user_active on stories (user_id) where expires_at > now();

create table story_views (
    story_id uuid not null references stories(id) on delete cascade,
    viewer_id uuid not null references profiles(id) on delete cascade,
    viewed_at timestamptz not null default now(),
    primary key (story_id, viewer_id)
);

create table story_mentions (
    story_id uuid not null references stories(id) on delete cascade,
    mentioned_user_id uuid not null references profiles(id) on delete cascade,
    primary key (story_id, mentioned_user_id)
);
