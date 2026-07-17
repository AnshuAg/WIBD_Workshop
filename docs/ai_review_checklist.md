# AI-Generated Data Model: One-Page Review Checklist

Before you merge anything an AI assistant wrote — dbt model, SQL, test — run it
through this. Every question here caught a real issue in the workshop pipeline;
none are hypothetical.

## 1. Does the filter logic match the *rule*, or a *pattern* that usually implies the rule?

A filter like `WHERE invoice_no NOT LIKE 'C%'` encodes "assume anything not
prefixed C is a real sale" — a pattern, not the rule ("a completed, priced sale").
Ask: what would slip through this filter without matching the pattern? In this
dataset, two `-£11,062.06` bad-debt adjustments did exactly that.

**Ask the AI:** "What's the actual business rule this filter is trying to
enforce, and does the SQL enforce that rule directly, or a proxy for it?"

## 2. Does every `NOT NULL` / uniqueness test reflect reality, or an assumption?

A `not_null` test on a column that's legitimately absent 25% of the time (guest
checkouts, in this dataset) will break CI on correct data. A test that's too
strict is exactly as dangerous as a filter that's too loose — both cause silent
harm, just in opposite directions (blocking good data vs. admitting bad data).

**Ask the AI:** "Show me rows where this column is null today. Are they invalid,
or a real case this table needs to support?"

## 3. Would the fix survive the *next* instance of the same problem?

A fix that special-cases the exact failing row (a specific `stock_code`, a
specific ID) passes today's test and reintroduces the same class of bug the next
time it shows up in a different shape.

**Ask the AI:** "Would this fix still work if the same problem showed up with a
different value?"

## 4. Did row count change, and can you explain why, exactly?

Compare row counts between each layer (bronze → staging → mart). A drop you can't
explain in one sentence is a silent filter doing more than you asked for.

## 5. Are non-obvious categories (non-product rows, cancellations, adjustments,
duplicates) handled explicitly, or did they just happen to fall out of a filter
written for something else?

If a `WHERE quantity > 0` filter happens to also remove postage/fee line items,
that's not a design decision — it's an accident that will confuse the next person
who tightens the filter and reintroduces them.

## 6. Would you accept this from a junior engineer without asking a follow-up
question?

If the honest answer is no — because the logic is plausible but you can't yet
say *why* it's right — that's the signal to go check the data yourself before
merging, not after something breaks.
