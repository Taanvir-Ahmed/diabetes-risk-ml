# 01_import_clean.R
# Read the NHANES files, merge the three cycles, define the outcome and
# the predictors, and apply the inclusion rules.
# Output: data/processed/analysis_data.rds and output/flow.csv

source("R/00_setup.R")

read_cycle <- function(s) {
  rd <- function(t) read_xpt(file.path("data/raw", paste0(t, "_", s, ".XPT")))

  demo <- rd("DEMO") |>
    select(SEQN, SDDSRVYR, RIDSTATR, RIAGENDR, RIDAGEYR, RIDRETH3,
           DMDEDUC2, INDFMPIR, RIDEXPRG, WTMEC2YR, SDMVSTRA, SDMVPSU)
  bmx  <- rd("BMX") |> select(SEQN, BMXBMI, BMXWAIST)
  bpx  <- rd("BPX") |> select(SEQN, BPXSY1, BPXSY2, BPXSY3, BPXDI1, BPXDI2, BPXDI3)
  ghb  <- rd("GHB") |> select(SEQN, LBXGH)
  glu  <- rd("GLU") |> select(SEQN, LBXGLU)
  diq  <- rd("DIQ") |> select(SEQN, DIQ010)
  tc   <- rd("TCHOL") |> select(SEQN, LBXTC)
  hdl  <- rd("HDL") |> select(SEQN, LBDHDD)
  smq  <- rd("SMQ") |> select(SEQN, SMQ020, SMQ040)
  paq  <- rd("PAQ") |> select(SEQN, PAQ650, PAQ665)
  mcq  <- rd("MCQ") |> select(SEQN, MCQ300C)

  Reduce(function(a, b) left_join(a, b, by = "SEQN"),
         list(demo, bmx, bpx, ghb, glu, diq, tc, hdl, smq, paq, mcq))
}

raw <- bind_rows(lapply(c("H", "I", "J"), read_cycle))

# Helper: mean of the available blood pressure readings.
# A diastolic value of 0 is not a real reading, so it is set to missing.
row_mean <- function(df) {
  m <- as.matrix(df)
  m[m == 0] <- NA
  out <- rowMeans(m, na.rm = TRUE)
  out[is.nan(out)] <- NA
  out
}

dat <- raw |>
  mutate(
    cycle = factor(SDDSRVYR, levels = 8:10,
                   labels = c("2013-14", "2015-16", "2017-18")),
    sex = factor(RIAGENDR, levels = 1:2, labels = c("Male", "Female")),
    age = RIDAGEYR,
    age_group = cut(age, c(19, 39, 59, 79), labels = c("20-39", "40-59", "60-79")),
    ethnicity = case_when(
      RIDRETH3 %in% c(1, 2) ~ "Hispanic",
      RIDRETH3 == 3 ~ "White",
      RIDRETH3 == 4 ~ "Black",
      RIDRETH3 == 6 ~ "Asian",
      RIDRETH3 == 7 ~ "Other"),
    ethnicity = factor(ethnicity, levels = c("White", "Black", "Hispanic", "Asian", "Other")),
    education = case_when(
      DMDEDUC2 %in% 1:2 ~ "Less than high school",
      DMDEDUC2 == 3 ~ "High school",
      DMDEDUC2 %in% 4:5 ~ "Some college or more"),
    education = factor(education, levels = c("Less than high school", "High school",
                                             "Some college or more")),
    income = case_when(
      INDFMPIR < 1.3 ~ "Low",
      INDFMPIR <= 3.5 ~ "Middle",
      INDFMPIR > 3.5 ~ "High",
      TRUE ~ "Missing"),
    income = factor(income, levels = c("Low", "Middle", "High", "Missing")),
    bmi = BMXBMI,
    waist = BMXWAIST,
    sbp = row_mean(pick(BPXSY1, BPXSY2, BPXSY3)),
    dbp = row_mean(pick(BPXDI1, BPXDI2, BPXDI3)),
    total_chol = LBXTC,
    hdl = LBDHDD,
    smoking = case_when(
      SMQ020 == 2 ~ "Never",
      SMQ020 == 1 & SMQ040 == 3 ~ "Former",
      SMQ020 == 1 & SMQ040 %in% 1:2 ~ "Current"),
    smoking = factor(smoking, levels = c("Never", "Former", "Current")),
    active = case_when(
      PAQ650 == 1 | PAQ665 == 1 ~ "Yes",
      PAQ650 == 2 & PAQ665 == 2 ~ "No"),
    active = factor(active, levels = c("No", "Yes")),
    family_history = case_when(MCQ300C == 1 ~ "Yes", MCQ300C == 2 ~ "No"),
    family_history = factor(family_history, levels = c("No", "Yes")),
    hba1c = LBXGH,
    fpg = LBXGLU,
    # Outcome: undiagnosed diabetes (HbA1c >= 6.5% or fasting glucose >= 126 mg/dL)
    undiag_dm = as.integer(hba1c >= 6.5 | (!is.na(fpg) & fpg >= 126)),
    weight = WTMEC2YR / 3,            # combined weight for three cycles
    strata = SDMVSTRA,
    psu = SDMVPSU
  )

# Inclusion steps, counted for the flow table
predictors <- c("age", "sex", "ethnicity", "education", "income", "bmi", "waist",
                "sbp", "dbp", "total_chol", "hdl", "smoking", "active",
                "family_history")

flow <- tibble(step = "All NHANES participants 2013-2018", n = nrow(dat))
add_step <- function(d, label) {
  force(d)
  flow <<- bind_rows(flow, tibble(step = label, n = nrow(d)))
  d
}

analysis <- dat |>
  filter(RIDSTATR == 2) |> add_step("Examined in the mobile exam centre") |>
  filter(age >= 20, age <= 79) |> add_step("Aged 20-79") |>
  filter(is.na(RIDEXPRG) | RIDEXPRG != 1) |> add_step("Not pregnant") |>
  filter(DIQ010 %in% c(2, 3)) |> add_step("No previous diabetes diagnosis") |>
  filter(!is.na(hba1c)) |> add_step("HbA1c measured") |>
  filter(if_all(all_of(predictors), ~ !is.na(.x))) |>
  add_step("No missing predictors (complete cases)")

analysis <- analysis |>
  select(SEQN, cycle, all_of(predictors), age_group, hba1c, fpg, undiag_dm,
         weight, strata, psu)

write.csv(flow, "output/flow.csv", row.names = FALSE)
saveRDS(analysis, "data/processed/analysis_data.rds")

cat("Final sample:", nrow(analysis), "people,",
    sum(analysis$undiag_dm), "with undiagnosed diabetes\n")
