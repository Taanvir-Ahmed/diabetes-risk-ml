# How sure is the model? Predicting undiagnosed type 2 diabetes with simple machine learning

A small health data science project in R. I used NHANES 2013-2018 (11,240 US adults without a diabetes diagnosis) to predict undiagnosed type 2 diabetes from routine measures: age, waist, BMI, blood pressure, cholesterol, smoking, physical activity, family history and a few social factors.

I compared logistic regression, LASSO, random forest and gradient boosting. Most projects stop at the AUC. This one also looks at calibration, uncertainty for each person (conformal prediction), fairness across sex, age and ethnic groups, SHAP explanations and decision curves for screening.

**Full report: [report/report.md](report/report.md)**

![Conformal prediction](figures/fig3_conformal.png)

## Main findings

- All four models had a test AUC of 0.76-0.78. Random forest and boosting were not better than logistic regression (AUC 0.779, 95% CI 0.747-0.808).
- Calibration was good. The average predicted risk matched the observed 5.0%, and LASSO had the best calibration slope (0.98).
- Standard conformal prediction gave 90% coverage overall but 0% for people with diabetes, because the outcome is rare. Class-conditional conformal prediction gave about 90% for both groups and labelled 39% of people as "uncertain" ({No, Yes}).
- The AUC was 0.85 for ages 20-39 but about 0.70 for ages 40-79. The boosting model under-predicted risk for Asian Americans (observed/expected 1.63, 95% CI 1.14-2.27); logistic regression did not.
- Age, waist, HDL cholesterol and ethnicity drove the predictions in both models. Risk rose above a waist of about 95 cm and an HDL below about 45 mg/dL.
- In decision curve analysis the models beat "test everyone" for risk thresholds of 2-13%. At a 3% threshold, testing half of the people would find 89% of the hidden cases.

The data are cross-sectional and from the US, so this is about finding existing undiagnosed diabetes in a US sample, not about predicting future diabetes in Finland. See the limitations in the report.

## Repository structure

```
data/raw/            README.md data log (the NHANES .XPT files are downloaded by R/download_data.R)
data/processed/      cleaned data and fitted models (made by the scripts, not on GitHub)
R/                   analysis scripts, run in order
  00_setup.R           packages, settings, plot style
  download_data.R      downloads the 33 NHANES files from the CDC website
  01_import_clean.R    merge cycles, define outcome and predictors, inclusion flow
  02_descriptive.R     Table 1 and survey-weighted prevalence
  03_models.R          train/calibration/test split, tuning, four models
  04_evaluation.R      AUC, calibration, Brier score, bootstrap CIs
  05_conformal.R       standard and class-conditional conformal prediction
  06_fairness.R        performance and calibration by sex, age and ethnicity
  07_shap.R            SHAP values (exact for logistic, Monte Carlo for boosting)
  08_decision_curve.R  net benefit for HbA1c screening
output/              result tables (csv)
figures/             figures used in the report
report/report.md     the report
run_all.R            runs everything
```

## How to run

1. Install R (4.3 or newer) and the packages:
   ```r
   install.packages(c("haven", "dplyr", "tidyr", "ggplot2", "patchwork", "glmnet",
                      "ranger", "gbm", "pROC", "survey", "scales"))
   ```
2. Open `diabetes-risk-ml.Rproj` in RStudio.
3. Run `source("run_all.R")`. It downloads the data if needed (about 80 MB) and runs all scripts in about two minutes. The seed is fixed, so the results should match the report.

## Data

NHANES is public data from the US National Center for Health Statistics: https://wwwn.cdc.gov/nchs/nhanes/. The data log in [data/raw/README.md](data/raw/README.md) lists every file, variable and cleaning step.

## Author

Tanvir Ahmed, MSc student in Statistical Data Analytics, Tampere University.
Other project: [Nordic cancer trends](https://github.com/Taanvir-Ahmed/nordic-cancer-trends).
