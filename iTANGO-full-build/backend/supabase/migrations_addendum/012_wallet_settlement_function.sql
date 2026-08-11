-- =============================================================================
-- Migration 012 (Phase 5 addendum): Atomic wallet settlement
-- Referenced by supabase/functions/tickets-purchase/index.ts. Implemented as
-- a Postgres function rather than application-code read-then-write, because
-- a balance check followed by a separate debit is a classic race condition
-- under concurrent requests (two simultaneous purchases could both pass the
-- balance check before either debit lands). This function makes the
-- check-and-debit atomic within a single transaction.
-- =============================================================================

create or replace function settle_ticket_purchase_from_wallet(
    p_ticket_purchase_id uuid,
    p_user_id uuid,
    p_amount numeric
)
returns void as $$
declare
    v_current_balance numeric;
begin
    -- Row-level lock prevents a concurrent call from reading a stale balance.
    select balance into v_current_balance
    from wallets
    where user_id = p_user_id
    for update;

    if v_current_balance is null then
        raise exception 'Wallet not found for user %', p_user_id;
    end if;

    if v_current_balance < p_amount then
        raise exception 'insufficient_balance';
    end if;

    insert into wallet_transactions (wallet_user_id, type, amount, reference)
    values (p_user_id, 'debit', p_amount, 'ticket_purchase:' || p_ticket_purchase_id);
    -- The apply_wallet_transaction trigger (migration 005) handles the
    -- balance decrement; we don't update wallets.balance directly here,
    -- to keep exactly one code path responsible for that mutation.

    update ticket_purchases set status = 'paid' where id = p_ticket_purchase_id;
end;
$$ language plpgsql security definer;

-- SECURITY DEFINER is required here because the calling user's own RLS
-- policies on `wallet_transactions` only permit SELECT, not INSERT (inserts
-- are service-role/function-only per migration 010's comment) — this
-- function is the one sanctioned path for a client-initiated wallet debit.
