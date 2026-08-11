-- =============================================================================
-- Migration 005: Payments, Wallets, Vouchers
-- =============================================================================

-- -----------------------------------------------------------------------------
-- payments — the ledger of record across ALL PSPs. Internal ledger is
-- source of truth (see Master Program Plan §9), not any PSP's dashboard.
-- -----------------------------------------------------------------------------
create table payments (
    id uuid primary key default uuid_generate_v4(),
    user_id uuid not null references profiles(id) on delete restrict,
    provider payment_provider not null,
    provider_reference text, -- PSP transaction id
    purpose payment_purpose not null,
    amount numeric(12,2) not null,
    currency text not null default 'NGN',
    status payment_status not null default 'initiated',
    metadata jsonb,
    created_at timestamptz not null default now(),
    updated_at timestamptz not null default now(),

    unique (provider, provider_reference)
);
create index idx_payments_user on payments (user_id);
create index idx_payments_status on payments (status);
create trigger trg_payments_updated_at before update on payments
    for each row execute function set_updated_at();

alter table ticket_purchases
    add constraint fk_ticket_purchases_payment
    foreign key (payment_id) references payments(id) on delete set null;

-- -----------------------------------------------------------------------------
-- Split payments — a ticket_purchase can be funded by multiple payments
-- (e.g. 3 friends splitting one VIP table)
-- -----------------------------------------------------------------------------
create table split_payment_contributions (
    id uuid primary key default uuid_generate_v4(),
    ticket_purchase_id uuid not null references ticket_purchases(id) on delete cascade,
    payer_id uuid not null references profiles(id) on delete restrict,
    payment_id uuid not null references payments(id) on delete restrict,
    amount numeric(12,2) not null,
    created_at timestamptz not null default now()
);
create index idx_split_contrib_purchase on split_payment_contributions (ticket_purchase_id);

-- -----------------------------------------------------------------------------
-- wallets — internal cash-equivalent balance (top-ups, refunds land here)
-- -----------------------------------------------------------------------------
create table wallets (
    user_id uuid primary key references profiles(id) on delete cascade,
    balance numeric(12,2) not null default 0,
    currency text not null default 'NGN',
    updated_at timestamptz not null default now(),

    constraint balance_non_negative check (balance >= 0)
);

create table wallet_transactions (
    id uuid primary key default uuid_generate_v4(),
    wallet_user_id uuid not null references wallets(user_id) on delete cascade,
    type wallet_txn_type not null,
    amount numeric(12,2) not null,
    reference text, -- e.g. 'refund:ticket_purchase:<id>' or 'topup:payment:<id>'
    created_at timestamptz not null default now(),

    constraint amount_positive check (amount > 0)
);
create index idx_wallet_txns_wallet on wallet_transactions (wallet_user_id, created_at desc);

create or replace function apply_wallet_transaction()
returns trigger as $$
begin
    if new.type = 'credit' then
        update wallets set balance = balance + new.amount, updated_at = now() where user_id = new.wallet_user_id;
    else
        update wallets set balance = balance - new.amount, updated_at = now() where user_id = new.wallet_user_id;
    end if;
    return new;
end;
$$ language plpgsql;

create trigger trg_apply_wallet_transaction after insert on wallet_transactions
    for each row execute function apply_wallet_transaction();

-- -----------------------------------------------------------------------------
-- vouchers — business-funded loyalty currency. Separate ledger from wallets
-- (see design-decisions doc §2 for rationale).
-- -----------------------------------------------------------------------------
create table vouchers (
    id uuid primary key default uuid_generate_v4(),
    issuer_business_id uuid not null references businesses(id) on delete cascade,
    title text not null,
    description text,
    value numeric(12,2) not null,
    currency text not null default 'NGN',
    min_energy_score integer default 0, -- e.g. only Top-5% users can claim
    total_quantity integer,
    claimed_quantity integer not null default 0,
    expires_at timestamptz not null,
    created_at timestamptz not null default now(),

    constraint claimed_within_total check (total_quantity is null or claimed_quantity <= total_quantity)
);
create index idx_vouchers_issuer on vouchers (issuer_business_id);
create index idx_vouchers_active on vouchers (expires_at) where expires_at > now();

create type voucher_redemption_status as enum ('claimed', 'redeemed', 'expired');
create table voucher_redemptions (
    id uuid primary key default uuid_generate_v4(),
    voucher_id uuid not null references vouchers(id) on delete cascade,
    user_id uuid not null references profiles(id) on delete cascade,
    status voucher_redemption_status not null default 'claimed',
    claimed_at timestamptz not null default now(),
    redeemed_at timestamptz,

    unique (voucher_id, user_id)
);
create index idx_voucher_redemptions_user on voucher_redemptions (user_id);

create or replace function bump_voucher_claimed_count()
returns trigger as $$
begin
    update vouchers set claimed_quantity = claimed_quantity + 1 where id = new.voucher_id;
    return new;
end;
$$ language plpgsql;

create trigger trg_voucher_claimed after insert on voucher_redemptions
    for each row execute function bump_voucher_claimed_count();

-- -----------------------------------------------------------------------------
-- Organizer payouts
-- -----------------------------------------------------------------------------
create type payout_status as enum ('requested', 'processing', 'paid', 'failed');
create table organizer_payouts (
    id uuid primary key default uuid_generate_v4(),
    organizer_id uuid not null references profiles(id) on delete restrict,
    event_id uuid references events(id) on delete set null,
    amount numeric(12,2) not null,
    currency text not null default 'NGN',
    status payout_status not null default 'requested',
    bank_details jsonb, -- tokenized/reference only, never raw account numbers
    requested_at timestamptz not null default now(),
    paid_at timestamptz
);
create index idx_organizer_payouts_organizer on organizer_payouts (organizer_id);
