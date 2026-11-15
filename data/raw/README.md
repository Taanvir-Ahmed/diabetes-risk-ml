# Data log

## Source

NHANES (National Health and Nutrition Examination Survey), run by the US National Center for Health Statistics. The files are public and free: https://wwwn.cdc.gov/nchs/nhanes/

I used three 2-year cycles: 2013-2014 (suffix H), 2015-2016 (I) and 2017-2018 (J). I stopped at 2017-2018 because the 2019-2020 cycle was cut short by COVID-19 and is released in a different format.

The .XPT files are not stored in the repository (about 80 MB). Run `R/download_data.R` to get them from the CDC website. I checked the row counts after downloading (for example DEMO_J has 9,254 rows and GHB_J has 6,401), and they match the CDC documentation.

## Files used

| File | Content | Variables used |
|---|---|---|
| DEMO | Demographics and survey design | RIAGENDR, RIDAGEYR, RIDRETH3, DMDEDUC2, INDFMPIR, RIDEXPRG, RIDSTATR, WTMEC2YR, SDMVSTRA, SDMVPSU |
| BMX | Body measures | BMXBMI, BMXWAIST |
| BPX | Blood pressure | BPXSY1-3, BPXDI1-3 |
| GHB | Glycohemoglobin | LBXGH (HbA1c, %) |
| GLU | Fasting plasma glucose (morning subsample) | LBXGLU (mg/dL) |
| DIQ | Diabetes questionnaire | DIQ010 (ever told you have diabetes) |
| TCHOL | Total cholesterol | LBXTC |
| HDL | HDL cholesterol | LBDHDD |
| SMQ | Smoking | SMQ020, SMQ040 |
| PAQ | Physical activity | PAQ650, PAQ665 |
| MCQ | Medical conditions | MCQ300C (close relative had diabetes) |

## Cleaning steps (R/01_import_clean.R)

1. Read the 33 files and merged them by SEQN (person ID). The three cycles were stacked into one data set.
2. Blood pressure is the mean of up to three readings. A diastolic value of 0 was set to missing.
3. Outcome: undiagnosed diabetes = HbA1c >= 6.5% or fasting glucose >= 126 mg/dL, in people who answered "no" or "borderline" to DIQ010. Fasting glucose is only measured in about half of the people (the morning subsample). For the others the outcome is based on HbA1c only.
4. Smoking: never (fewer than 100 cigarettes in life), former, current.
5. Physically active: yes if the person does any moderate or vigorous recreational activity.
6. Income: family income to poverty ratio, grouped as low (<1.3), middle (1.3-3.5), high (>3.5). About 9% had no income value, so I kept them as a "Missing" group instead of dropping them.
7. Survey weight for the combined data: WTMEC2YR / 3, as recommended by NCHS when three cycles are combined.

## Inclusion

The number of people after each step is in `output/flow.csv`:

| Step | n |
|---|---|
| All participants 2013-2018 | 29,400 |
| Examined in the mobile exam centre | 28,061 |
| Aged 20-79 | 15,270 |
| Not pregnant | 15,080 |
| No previous diabetes diagnosis | 12,968 |
| HbA1c measured | 12,396 |
| No missing predictors | 11,240 |

Age 80+ is top-coded as 80 in NHANES, so I left those people out.
