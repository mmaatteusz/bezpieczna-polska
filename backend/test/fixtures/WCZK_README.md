# WCZK fixtures

`wczk-podkarpackie.html` is a reduced real response fetched on 2026-09-21 from
https://rzeszow.uw.gov.pl/wczk/ostrzezenia . Kept: canonical URL, all six notice
containers, upstream map element identifiers, complete headings and paragraph text.
Removed: navigation, tracking scripts, CSS, images and SVG paths (which are not
geographical coordinates). No warning text or validity has been invented.

`wczk.test.ts` mutates copies only to test broken structure and duplicate IDs.
`correlation.test.ts` and the Flutter incident fixture are explicitly synthetic
test reports, never production fallback data.
