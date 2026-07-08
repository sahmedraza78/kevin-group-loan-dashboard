-- Reference dump only (pulled live from Supabase project yrvyavcunqpjnxrsqbnh).
-- Not meant to be executed. Describes the data shape index.html depends on.

-- entities: one row per business entity
--   id bigint, name text, entity_type text, notes text

-- properties: one row per property, linked to an entity
--   id bigint, entity_id bigint (fk -> entities.id), address text,
--   purchased_on date, purchase_price numeric, rented_to text, weekly_rent numeric

-- loans: one row per loan facility, linked to a property
--   id bigint, property_id bigint (fk -> properties.id), odoo_account_code text,
--   loan_account_number text, lender text, interest_rate numeric,
--   repayment_frequency_desc text, linked_in_odoo boolean,
--   odoo_short_code text, odoo_account_id integer  -- odoo_account_id is the stable
--   internal Odoo account.account id used by the odoo-sync Edge Function to pull
--   journal lines for this loan

-- loan_transactions: one row per synced Odoo journal line
--   id bigint, loan_id bigint (fk -> loans.id), txn_date date,
--   txn_type text ('interest' | 'fee' | 'repayment' | others), debit numeric,
--   credit numeric, label text, odoo_move_number text, source text,
--   odoo_line_id bigint unique  -- non-null for every row synced from the live
--   Odoo API; used to dedupe and to prove no data was hand-entered

-- guarantees: one row per loan guarantee/security
--   id bigint, loan_id bigint (fk -> loans.id), guarantor_entity_id bigint,
--   guarantor_person text, security_type text, description text

-- sync_log: one row per odoo-sync Edge Function run
--   id bigint, ran_at timestamptz, rows_fetched int, rows_inserted int,
--   status text ('ok' | 'error'), message text

-- loan_balances: a view (not shown here) that rolls up loan_transactions into
-- per-loan running totals: loan_id, property, entity, initial_funding,
-- cumulative_interest, cumulative_fees, cumulative_repayments, outstanding_balance

-- The single RPC the dashboard calls, exactly as currently deployed:

CREATE OR REPLACE FUNCTION public.get_dashboard_data()
 RETURNS jsonb
 LANGUAGE sql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  select jsonb_build_object(
    'accounts', (
      select coalesce(jsonb_agg(jsonb_build_object(
        'loan_id', lb.loan_id,
        'property', lb.property,
        'entity', lb.entity,
        'funding', lb.initial_funding,
        'interest', lb.cumulative_interest,
        'fee', lb.cumulative_fees,
        'repay', lb.cumulative_repayments,
        'outstanding', lb.outstanding_balance,
        'principal_paid', lb.cumulative_repayments - lb.cumulative_interest - lb.cumulative_fees
      )), '[]'::jsonb)
      from loan_balances lb
      where lb.initial_funding > 0 or lb.cumulative_interest > 0 or lb.cumulative_repayments > 0
    ),
    'monthly', (
      select coalesce(jsonb_agg(m), '[]'::jsonb)
      from (
        select
          t.loan_id,
          to_char(date_trunc('month', t.txn_date), 'YYYY-MM') as ym,
          sum(t.credit) filter (where t.txn_type = 'interest') as interest,
          sum(t.credit) filter (where t.txn_type = 'fee') as fee,
          sum(t.debit) filter (where t.txn_type = 'repayment') as repay
        from loan_transactions t
        group by t.loan_id, date_trunc('month', t.txn_date)
        order by t.loan_id, date_trunc('month', t.txn_date)
      ) m
    ),
    'unlinked', (
      select coalesce(jsonb_agg(jsonb_build_object(
        'property', p.address,
        'entity', e.name,
        'lender', l.lender,
        'loan_account', l.loan_account_number
      )), '[]'::jsonb)
      from loans l
      join properties p on p.id = l.property_id
      join entities e on e.id = p.entity_id
      where l.linked_in_odoo = false
        and p.address not in ('7 Shiraz Av, Dapto', '24 Flamingo Drive Cameron Park')
    ),
    'no_loan_account', (
      select coalesce(jsonb_agg(jsonb_build_object(
        'property', p.address,
        'entity', e.name,
        'note', case
          when p.address = '24 Flamingo Drive Cameron Park' then 'Paid from an existing SDA account - no separate loan facility'
          else 'Land held outright - interest capitalised, no loan account'
        end
      )), '[]'::jsonb)
      from loans l
      join properties p on p.id = l.property_id
      join entities e on e.id = p.entity_id
      where p.address in ('7 Shiraz Av, Dapto', '24 Flamingo Drive Cameron Park')
    ),
    'last_sync', (
      select max(ran_at) from sync_log where status = 'ok'
    )
  );
$function$;
