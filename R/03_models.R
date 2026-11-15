# 03_models.R
# Split the data, tune and fit four models, and predict for the
# calibration and test sets.
#   Training set    (50%): fit and tune the models (5-fold cross-validation)
#   Calibration set (20%): only used for conformal prediction (script 05)
#   Test set        (30%): final evaluation, never used for fitting
# Output: data/processed/models.rds, data/processed/predictions.rds,
#         output/cv_auc.csv, output/model_settings.csv

source("R/00_setup.R")
d <- readRDS("data/processed/analysis_data.rds")

predictors <- c("age", "sex", "ethnicity", "education", "income", "bmi", "waist",
                "sbp", "dbp", "total_chol", "hdl", "smoking", "active",
                "family_history")
f <- as.formula(paste("undiag_dm ~", paste(predictors, collapse = " + ")))

# ---- Stratified split -----------------------------------------------------
split_one <- function(n) sample(rep(c("train", "calib", "test"),
                                    times = round(n * c(0.5, 0.2, 0.3)))[1:n])
d$set <- NA_character_
for (y in 0:1) {
  idx <- which(d$undiag_dm == y)
  d$set[idx] <- split_one(length(idx))
}
d$set[is.na(d$set)] <- "train"
train <- filter(d, set == "train")
calib <- filter(d, set == "calib")
test  <- filter(d, set == "test")
print(table(d$set, d$undiag_dm))

# Design matrix for glmnet (same columns for every data set)
mm <- function(data) model.matrix(f, data)[, -1]

# ---- Fit functions ------------------------------------------------------------
fit_logistic <- function(tr) glm(f, data = tr, family = binomial)
pred_logistic <- function(m, nd) predict(m, nd, type = "response")

fit_lasso <- function(tr) cv.glmnet(mm(tr), tr$undiag_dm, family = "binomial",
                                    alpha = 1, nfolds = 5)
pred_lasso <- function(m, nd) as.vector(predict(m, mm(nd), s = "lambda.min",
                                                type = "response"))

fit_rf <- function(tr, mtry = 3, node = 50) {
  tr$y <- factor(tr$undiag_dm)
  ranger(as.formula(paste("y ~", paste(predictors, collapse = " + "))),
         data = tr, probability = TRUE, num.trees = 500,
         mtry = mtry, min.node.size = node, seed = 1)
}
pred_rf <- function(m, nd) predict(m, nd)$predictions[, "1"]

fit_gbm <- function(tr, n_trees = 1000) {
  gbm(f, data = tr, distribution = "bernoulli", n.trees = n_trees,
      interaction.depth = 2, shrinkage = 0.01, bag.fraction = 0.5,
      n.minobsinnode = 20)
}
pred_gbm <- function(m, nd) predict(m, nd, n.trees = m$n.trees, type = "response")

# ---- Tuning with 5-fold CV on the training set ----------------------------------
folds <- sample(rep(1:5, length.out = nrow(train)))
cv_auc <- function(fit_fun, pred_fun, ...) {
  p <- numeric(nrow(train))
  for (k in 1:5) {
    m <- fit_fun(train[folds != k, ], ...)
    p[folds == k] <- pred_fun(m, train[folds == k, ])
  }
  as.numeric(auc(train$undiag_dm, p, quiet = TRUE))
}

# Random forest: small grid for mtry and minimum node size
rf_grid <- expand.grid(mtry = c(2, 3, 5), node = c(10, 50, 100))
rf_grid$auc <- mapply(function(m, n) cv_auc(fit_rf, pred_rf, mtry = m, node = n),
                      rf_grid$mtry, rf_grid$node)
rf_best <- rf_grid[which.max(rf_grid$auc), ]
print(rf_grid)

# Boosting: number of trees chosen by gbm's own 5-fold CV
gbm_cv <- gbm(f, data = train, distribution = "bernoulli", n.trees = 3000,
              interaction.depth = 2, shrinkage = 0.01, bag.fraction = 0.5,
              n.minobsinnode = 20, cv.folds = 5)
gbm_trees <- gbm.perf(gbm_cv, method = "cv", plot.it = FALSE)
cat("Boosting: best number of trees =", gbm_trees, "\n")

cv_results <- tibble(
  model = names(model_cols),
  cv_auc = c(cv_auc(fit_logistic, pred_logistic),
             cv_auc(fit_lasso, pred_lasso),
             rf_best$auc,
             cv_auc(fit_gbm, pred_gbm, n_trees = gbm_trees))
)
print(cv_results)
write.csv(cv_results, "output/cv_auc.csv", row.names = FALSE)

# ---- Final models on the full training set --------------------------------------
models <- list(
  "Logistic"      = fit_logistic(train),
  "LASSO"         = fit_lasso(train),
  "Random forest" = fit_rf(train, rf_best$mtry, rf_best$node),
  "Boosting"      = fit_gbm(train, gbm_trees)
)
pred_funs <- list("Logistic" = pred_logistic, "LASSO" = pred_lasso,
                  "Random forest" = pred_rf, "Boosting" = pred_gbm)

predict_all <- function(nd) {
  out <- nd |> select(SEQN, set, undiag_dm, sex, age_group, ethnicity)
  for (m in names(models)) out[[m]] <- pred_funs[[m]](models[[m]], nd)
  out
}
preds <- bind_rows(predict_all(calib), predict_all(test))

settings <- tibble(
  model = names(model_cols),
  settings = c("All 14 predictors, linear terms",
               sprintf("lambda.min = %.4f, %d non-zero coefficients",
                       models$LASSO$lambda.min,
                       sum(coef(models$LASSO, s = "lambda.min")[-1] != 0)),
               sprintf("500 trees, mtry = %d, min node size = %d",
                       rf_best$mtry, rf_best$node),
               sprintf("%d trees, depth 2, learning rate 0.01", gbm_trees))
)
write.csv(settings, "output/model_settings.csv", row.names = FALSE)

# Odds ratios from the logistic model (easy to read)
or <- exp(cbind(OR = coef(models$Logistic), confint.default(models$Logistic)))
or <- tibble(term = rownames(or), OR = or[, 1], lower = or[, 2], upper = or[, 3]) |>
  filter(term != "(Intercept)") |>
  mutate(across(OR:upper, ~ round(.x, 2)))
write.csv(or, "output/logistic_odds_ratios.csv", row.names = FALSE)

saveRDS(list(models = models, train = train, calib = calib, test = test,
             predictors = predictors, formula = f),
        "data/processed/models.rds")
saveRDS(preds, "data/processed/predictions.rds")
