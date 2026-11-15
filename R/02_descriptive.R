# 02_descriptive.R
# Table 1 (characteristics by outcome) and survey-weighted prevalence.
# Output: output/table1.csv, output/prevalence.csv

source("R/00_setup.R")
d <- readRDS("data/processed/analysis_data.rds")

# ---- Table 1 ---------------------------------------------------------------
num_vars <- c(age = "Age (years)", bmi = "BMI (kg/m2)", waist = "Waist (cm)",
              sbp = "Systolic BP (mmHg)", dbp = "Diastolic BP (mmHg)",
              total_chol = "Total cholesterol (mg/dL)", hdl = "HDL (mg/dL)",
              hba1c = "HbA1c (%)")
cat_vars <- c(sex = "Sex", ethnicity = "Ethnicity", education = "Education",
              income = "Income (poverty ratio)", smoking = "Smoking",
              active = "Physically active", family_history = "Family history of diabetes")

grp <- list(All = d, `No diabetes` = filter(d, undiag_dm == 0),
            `Undiagnosed diabetes` = filter(d, undiag_dm == 1))

rows <- list(tibble(variable = "N", level = "",
                    !!!lapply(grp, function(g) format(nrow(g), big.mark = ","))))

for (v in names(num_vars)) {
  rows[[v]] <- tibble(variable = num_vars[[v]], level = "mean (SD)",
                      !!!lapply(grp, function(g)
                        sprintf("%.1f (%.1f)", mean(g[[v]]), sd(g[[v]]))))
}
for (v in names(cat_vars)) {
  for (l in levels(d[[v]])) {
    rows[[paste(v, l)]] <- tibble(variable = cat_vars[[v]], level = l,
                                  !!!lapply(grp, function(g)
                                    sprintf("%d (%.1f%%)", sum(g[[v]] == l),
                                            100 * mean(g[[v]] == l))))
  }
}
table1 <- bind_rows(rows)

# p-values: t-test for numbers, chi-squared test for categories
pvals <- c(sapply(names(num_vars), function(v) t.test(d[[v]] ~ d$undiag_dm)$p.value),
           sapply(names(cat_vars), function(v) chisq.test(table(d[[v]], d$undiag_dm))$p.value))
pv <- tibble(variable = c(num_vars, cat_vars),
             p_value = ifelse(pvals < 0.001, "<0.001", sprintf("%.3f", pvals)))
table1 <- left_join(table1, pv, by = "variable") |>
  group_by(variable) |>
  mutate(p_value = ifelse(row_number() == 1, p_value, "")) |>
  ungroup() |>
  mutate(p_value = ifelse(is.na(p_value), "", p_value))

write.csv(table1, "output/table1.csv", row.names = FALSE)
print(table1, n = 50)

# ---- Survey-weighted prevalence -------------------------------------------
# NHANES is not a simple random sample. To estimate the prevalence in the US
# adult population we use the MEC weights, strata and PSUs.
# (The design is set up on the analysis sample, which is a simplification.)
options(survey.lonely.psu = "adjust")
des <- svydesign(ids = ~psu, strata = ~strata, weights = ~weight,
                 nest = TRUE, data = d)

prev_row <- function(by = NULL) {
  if (is.null(by)) {
    est <- svymean(~undiag_dm, des)
    ci <- confint(est)
    return(tibble(group = "All", level = "All", n = nrow(d),
                  unweighted = mean(d$undiag_dm),
                  weighted = coef(est)[1], lower = ci[1], upper = ci[2]))
  }
  est <- svyby(~undiag_dm, as.formula(paste0("~", by)), des, svymean)
  ci <- confint(est)
  tibble(group = by, level = as.character(est[[by]]),
         n = as.vector(table(d[[by]])),
         unweighted = as.vector(tapply(d$undiag_dm, d[[by]], mean)),
         weighted = coef(est), lower = ci[, 1], upper = ci[, 2])
}

prev <- bind_rows(prev_row(), prev_row("sex"), prev_row("age_group"),
                  prev_row("ethnicity"))
prev <- mutate(prev, across(unweighted:upper, ~ round(100 * .x, 1)))
write.csv(prev, "output/prevalence.csv", row.names = FALSE)
print(prev)
