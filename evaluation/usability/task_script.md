# Usability session script (SUS target ≥ 68, at least 15 sellers)

Record for each task: success (yes/no), time in seconds, and any help
given.

1. "Open the app and check this tomato." Uses the camera on a prepared tomato.
2. "Check this banana hand using a photo already on the phone." Uses the gallery.
3. "Here is a dark or blurry photo. What does the app tell you to do?" Expected: the seller understands Uncertain and retakes.
4. "Find the result you got for the first tomato." Uses History.
5. "What would you do with this item based on the result?" Checks that the seller understands the advice.

After the tasks:

- Read the 10 SUS items aloud, in Kinyarwanda if preferred, using a
  validated translation. Score each from 1 (strongly disagree) to 5
  (strongly agree). Record q1–q10 in `sus_results.csv`.
- Ask two open questions:
  1. "Was anything on the result screen unclear?"
  2. "Would you use this at your stall? Why or why not?"

Score with `python evaluation/analysis.py sus evaluation/usability/sus_results.csv`.
