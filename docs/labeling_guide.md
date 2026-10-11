# HarvestShelf AI labeling guide (v0.1)

Label **only what is visible in the photo**. Don't use touch, smell or
what the seller tells you. If you can't decide from the photo, use
`unusable`.

Before full labeling, two labelers independently label at least 20% of
the images. Cohen's kappa must be at least 0.70 (`python -m src.clean`
checks this). Discuss the disagreements, update this guide, and bump the
version number.

## Labels

| Label | Meaning | Seller action |
|---|---|---|
| `fresh` | Normal selling quality | Sell at the normal price |
| `sell_soon` | Early visible change, still clearly good to use | Sell first |
| `discount_today` | Clear decline; needs a quick sale | Lower the price today |
| `spoilage_risk` | Mold-like marks, rot, leaking, severe bruising or other unacceptable decline | Remove from normal sale |
| `unusable` | Blurred, too dark, several items mixed, or not a supported crop | The app says Uncertain |

When torn between two labels, **pick the worse one**. Missing spoilage
costs more than an unnecessary warning.

## Tomato cues

| Label | What you see |
|---|---|
| fresh | Even colour for its ripeness stage; smooth, tight, glossy skin; green fresh calyx; no marks |
| sell_soon | Fully red or slightly over-ripe colour; small shallow marks; slight dullness; calyx starting to dry |
| discount_today | Wrinkled or dull skin; soft-looking flattened areas; several bruises; small closed cracks |
| spoilage_risk | Mold (white, grey, black fuzz); open cracks or leaking; dark sunken or water-soaked patches; rot at stem end |

## Green (cooking) banana cues

Cooking bananas are sold green, so yellowing itself is a sign of age.

| Label | What you see |
|---|---|
| fresh | Even green peel; firm-looking fingers; fresh pale crown cut; at most tiny scratches |
| sell_soon | Small brown or black bruise spots; slight yellowing; crown cut darkening |
| discount_today | Large bruised or blackened areas; clear yellowing; split peel without exposed flesh; dried crown |
| spoilage_risk | Mold on crown or peel; crown rot; exposed or leaking flesh; widespread black, sunken peel |

## Photo rules (collection and labeling)

- One tomato, or one banana hand or finger, fills most of the frame.
- Daylight or stall light. No flash glare.
- Keep faces, hands with jewellery, and shop signs out of the frame.
- Take 1 to 3 angles per item. They share one `batch_id`, so they always land in the same split.

## Reference photos

Add 3 to 5 agreed example photos per label and crop under
`docs/reference_photos/<crop>/<label>/` once the first collection day is
done.
