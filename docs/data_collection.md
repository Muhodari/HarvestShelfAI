# Data collection protocol

## Targets (proposal Section 3.7)

- Markets: at least 3 across Nyabihu and Rusizi. Days: at least 5.
- At least 300 usable images per label per crop, so at least 2,400 for tomatoes and green bananas.
- Plus about 200 `unusable` examples: blurred, dark, other produce, empty stall.
- At least 2 visits to each district in Month 2. Make up any shortfall at the start of Month 3.

Discount Today and Spoilage Risk are rare at stalls. **Buy a small batch,
keep it under normal stall conditions, and photograph it daily** until it
spoils. One purchase then covers all four labels. Record it as one
`batch_id` per item per day.

## Folder and file naming

```
data/raw/<YYYY-MM-DD>_<market>/<image_id>.jpg
e.g. data/raw/2026-11-03_kamembe/T0412.jpg
```

## metadata.csv (one row per photo)

| Column | Example | Notes |
|---|---|---|
| image_id | T0412 | unique |
| file | 2026-11-03_kamembe/T0412.jpg | path under data/raw |
| market | kamembe | |
| district | rusizi | |
| date | 2026-11-03 | |
| crop | tomato | `tomato`, `banana`, or `other` |
| phone_model | Tecno Spark 10 | |
| label_a | sell_soon | labeler A, from the labeling guide |
| label_b | sell_soon | labeler B; leave empty if not double-labelled |
| final_label | | set only after discussing a disagreement |
| batch_id | kamembe_2026-11-03_s04 | same item or batch on the same day; **this keeps splits leak-free** |
| notes | | optional |

## Consent and privacy

- Read the consent form to the seller before photographing at their stall.
- Photograph produce only. Crop or delete any photo that shows a face or a shop name.
- Keep `data/` off public repositories.

## After each collection day

1. Copy the photos into `data/raw/<date>_<market>/` and add rows to `metadata.csv`.
2. Run `python -m src.clean --force-kappa` to check quality and class counts. Use `--force-kappa` only until the 20% double-labelled sample is complete.
3. Note which labels are short and plan the next visit around them.
