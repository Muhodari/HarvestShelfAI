# Seller agreement study (Objective 3: +15 percentage points)

**Question:** do sellers agree more often with expert labels when they use
the app than when they sort by eye alone?

## Materials

- Two prepared batches, A and B, each of about 20 numbered items (tomatoes
  and green bananas) mixed across all four conditions. Number each item
  with a sticker (`A01`…`A20`, `B01`…`B20`).
- Before the sessions, **two experts** label every item from the labeling
  guide. They are an extension officer and the researcher, or two trained
  labelers. Settle any disagreement before the study starts. Record the
  result in `expert_labels.csv`.

## Procedure (per seller, about 20 minutes)

1. Get consent and record age group and smartphone experience.
2. **Counterbalance:** odd-numbered participants do batch A *without* the
   app and then batch B *with* it. Even-numbered participants do batch A
   *with* the app and then batch B *without* it. This balances batch
   difficulty and learning effects.
3. *Without app:* the seller puts each item into one of the four labels.
4. *With app:* the seller scans each item and then chooses a label. They
   may disagree with the app. Record the seller's final choice, not the
   app's.
5. Record each choice in `seller_sorts.csv`:
   `participant_id, condition (with_app|without_app), order (1|2), item_id, seller_label`.

## Analysis

```
python evaluation/analysis.py agreement evaluation/agreement_study/seller_sorts.csv evaluation/agreement_study/expert_labels.csv
```

The script reports per-seller agreement in each condition, the mean
difference in percentage points, and a one-sided Wilcoxon signed-rank
test. It also checks agreement by order to look for learning effects.
