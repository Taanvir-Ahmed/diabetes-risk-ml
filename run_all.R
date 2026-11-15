# run_all.R
# Runs the whole analysis from raw data to figures (about 3 minutes).
# Open diabetes-risk-ml.Rproj in RStudio (or set the working directory to the
# project folder) and run: source("run_all.R")

if (length(list.files("data/raw", pattern = "XPT$")) < 33) source("R/download_data.R")

scripts <- c("R/01_import_clean.R", "R/02_descriptive.R", "R/03_models.R",
             "R/04_evaluation.R", "R/05_conformal.R", "R/06_fairness.R",
             "R/07_shap.R", "R/08_decision_curve.R")
for (s in scripts) {
  message("\n==== Running ", s, " ====")
  source(s, echo = FALSE)
}
