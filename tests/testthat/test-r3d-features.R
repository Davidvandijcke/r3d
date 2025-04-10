context("R3D Package Feature Tests")

library(testthat)
library(R3D)
library(dplyr, warn.conflicts = FALSE)

###############################################################################
# 1) Functions to generate fake data for testing with RANDOM DISTRIBUTIONS
###############################################################################

# (A) Simple test data with random distributions and known constant effect
create_test_data <- function(n = 500, sample_size = 300, seed = 123, fuzzy = FALSE) {
  set.seed(seed)
  x <- runif(n, -1, 1)
  
  # Known, uniform effect = effect_size
  effect_size <- 3
  y_list <- vector("list", n)
  
  for (i in seq_len(n)) {
    if (x[i] < 0) {
      # Below cutoff: draw random mean and standard deviation
      mu_i <- rnorm(1, mean = 5 + 0.5 * x[i], sd = 1)
      sigma_i <- abs(rnorm(1, mean = 0.5, sd = 0.2))
      y_list[[i]] <- rnorm(sample_size, mean = mu_i, sd = sigma_i)
    } else {
      # Above cutoff: draw random mean and standard deviation with shifted mean
      mu_i <- rnorm(1, mean = 5 + 0.5 * x[i] + effect_size, sd = 1)
      sigma_i <- abs(rnorm(1, mean = 0.5, sd = 0.2))
      y_list[[i]] <- rnorm(sample_size, mean = mu_i, sd = sigma_i)
    }
  }
  
  t <- if (fuzzy) {
    # Generate treatment status T for fuzzy design
    p_t <- 0.1 + 0.8 * (x > 0)  # e.g., 10% below, 90% above
    p_t <- pmax(0, pmin(1, p_t))
    rbinom(n, 1, p_t)
  } else {
    NULL
  }
  
  list(
    x = x,
    y_list = y_list,
    t = t,
    true_effect = effect_size  # exactly effect_size at all quantiles
  )
}

# (B) Heterogeneous effect data with random distributions
create_hetero_effect_data <- function(n = 1000, seed = 456, sample_size = 200) {
  set.seed(seed)
  x <- runif(n, -1, 1)
  
  # Generate sample data with random distributions
  y_list <- vector("list", n)
  for (i in seq_len(n)) {
    if (x[i] < 0) {
      # Control group - random normal distribution
      mu_i <- rnorm(1, mean = 2 + x[i], sd = 0.5)
      sigma_i <- abs(rnorm(1, mean = 0.5, sd = 0.2))
      y_list[[i]] <- rnorm(sample_size, mean = mu_i, sd = sigma_i)
    } else {
      # Treatment group - mixture with random components
      mu_i1 <- rnorm(1, mean = 2 + x[i], sd = 0.5)
      sigma_i1 <- abs(rnorm(1, mean = 0.5, sd = 0.2))
      y_list[[i]] <- c(
        rnorm(sample_size / 2, mean = mu_i1, sd = sigma_i1),
        rnorm(sample_size / 2, mean = mu_i1 + 2, sd = sigma_i1)
      )
    }
  }
  
  # Calculate true treatment effect using simulation
  set.seed(9999)
  big_reps <- 50000
  q_grid <- seq(0.01, 0.99, 0.01)
  
  below_means <- rnorm(big_reps, mean = 2, sd = 0.5)
  below_sds <- abs(rnorm(big_reps, mean = 0.5, sd = 0.2))
  below_samples <- numeric(big_reps)
  
  above_means <- rnorm(big_reps, mean = 2, sd = 0.5)
  above_sds <- abs(rnorm(big_reps, mean = 0.5, sd = 0.2))
  above_samples <- numeric(big_reps * 2)
  
  for (i in 1:big_reps) {
    below_samples[i] <- rnorm(1, mean = below_means[i], sd = below_sds[i])
    above_samples[i] <- rnorm(1, mean = above_means[i], sd = above_sds[i])
    above_samples[i + big_reps] <- rnorm(1, mean = above_means[i] + 2, sd = above_sds[i])
  }
  
  below_quantiles <- quantile(below_samples, probs = q_grid)
  above_quantiles <- quantile(above_samples, probs = q_grid)
  true_effects <- above_quantiles - below_quantiles
  names(true_effects) <- as.character(q_grid)
  
  key_quantiles <- c(0.1, 0.25, 0.5, 0.75, 0.9)
  key_effects <- round(quantile(above_samples, probs = key_quantiles) - 
                         quantile(below_samples, probs = key_quantiles), 2)
  cat("True treatment effects at key quantiles:\n")
  print(key_effects)
  
  list(
    x = x,
    y_list = y_list,
    true_effects = true_effects
  )
}

################################################################################
# 1) Test r3d_bwselect() basic usage
################################################################################

test_that("r3d_bwselect() works for method='simple' and 'frechet' with sharp and fuzzy designs", {
  set.seed(101)
  # Sharp design
  n <- 50
  x <- runif(n, -1, 1)
  y_list <- lapply(seq_len(n), function(i) rnorm(30, mean = 2 + 0.5 * x[i]))
  
  # Simple method, sharp design
  bwres_simp_sharp <- r3d_bwselect(x, y_list, method = "simple", p = 1, fuzzy = FALSE)
  expect_equal(bwres_simp_sharp$method, "simple")
  expect_true(is.numeric(bwres_simp_sharp$h_star_num))
  expect_true(length(bwres_simp_sharp$h_star_num) > 1)  # per-quantile => vector
  expect_null(bwres_simp_sharp$h_star_den)  # No denominator bandwidth in sharp design
  
  # Frechet method, sharp design
  bwres_frech_sharp <- r3d_bwselect(x, y_list, method = "frechet", p = 1, fuzzy = FALSE)
  expect_equal(bwres_frech_sharp$method, "frechet")
  expect_true(is.numeric(bwres_frech_sharp$h_star_num))
  expect_length(bwres_frech_sharp$h_star_num, 1)  # single IMSE bandwidth
  expect_null(bwres_frech_sharp$h_star_den)
  
  # Fuzzy design
  t <- rbinom(n, 1, 0.5)
  bwres_simp_fuzzy <- r3d_bwselect(x, y_list, T = t, method = "simple", p = 1, fuzzy = TRUE)
  expect_true(is.numeric(bwres_simp_fuzzy$h_star_num))
  expect_true(is.numeric(bwres_simp_fuzzy$h_star_den))
  expect_true(length(bwres_simp_fuzzy$h_star_num) > 1)
  expect_length(bwres_simp_fuzzy$h_star_den, 1)
  
  bwres_frech_fuzzy <- r3d_bwselect(x, y_list, T = t, method = "frechet", p = 1, fuzzy = TRUE)
  expect_true(is.numeric(bwres_frech_fuzzy$h_star_num))
  expect_true(is.numeric(bwres_frech_fuzzy$h_star_den))
  expect_length(bwres_frech_fuzzy$h_star_num, 1)
  expect_length(bwres_frech_fuzzy$h_star_den, 1)
})

test_that("r3d_bwselect() properly handles edge cases", {
  set.seed(1010)
  n <- 30
  x <- runif(n, -1, 1)
  
  # Case 1: All observations on one side of cutoff
  x_one_side <- abs(x)  # all positive
  y_list <- lapply(seq_len(n), function(i) rnorm(20, mean = 3 + x_one_side[i]))
  expect_error(
    r3d_bwselect(x_one_side, y_list, method = "simple"))
  
  # Case 2: Very large variance in distributions
  y_list_var <- lapply(seq_len(n), function(i) {
    if (x[i] < 0) rnorm(20, mean = 2, sd = 1) else rnorm(20, mean = 2, sd = 10)
  })
  bw_var <- r3d_bwselect(x, y_list_var, method = "frechet")
  expect_true(is.numeric(bw_var$h_star_num))
  expect_false(is.na(bw_var$h_star_num))
})

################################################################################
# 2) Test r3d() usage for method='simple' and 'frechet' (sharp vs fuzzy)
################################################################################

test_that("r3d() runs for simple (sharp) with no errors", {
  set.seed(102)
  test_data <- create_test_data(n = 50, sample_size = 30, fuzzy = FALSE)
  out_simp <- r3d(X = test_data$x, Y_list = test_data$y_list, cutoff = 0, method = "simple", p = 1, boot = FALSE)
  
  expect_s3_class(out_simp, "r3d")
  expect_equal(out_simp$method, "simple")
  expect_false("boot_out" %in% names(out_simp$bootstrap))
  expect_equal(length(out_simp$tau), length(out_simp$q_grid))
  expect_true("w_plus" %in% names(out_simp))
  expect_true("w_minus" %in% names(out_simp))
  expect_equal(dim(out_simp$w_plus), c(50, length(out_simp$q_grid)))
  expect_true("results" %in% names(out_simp))
  expect_true("coefficients" %in% names(out_simp))
  expect_true("bootstrap" %in% names(out_simp))
  expect_true("inputs" %in% names(out_simp))
  expect_true("diagnostics" %in% names(out_simp))
  expect_equal(out_simp$tau, out_simp$results$tau)
  expect_equal(out_simp$q_grid, out_simp$results$q_grid)
})

test_that("r3d() runs for simple (fuzzy) with no errors", {
  set.seed(103)
  test_data <- create_test_data(n = 60, sample_size = 40, fuzzy = TRUE)
  out_simp_fuzzy <- r3d(X = test_data$x, Y_list = test_data$y_list, T = test_data$t, fuzzy = TRUE, method = "simple", p = 2)
  
  expect_s3_class(out_simp_fuzzy, "r3d")
  expect_true(out_simp_fuzzy$fuzzy)
  expect_true("alphaT_plus" %in% names(out_simp_fuzzy))
  expect_true("alphaT_minus" %in% names(out_simp_fuzzy))
  expect_false(is.null(out_simp_fuzzy$alphaT_plus))
  expect_false(is.null(out_simp_fuzzy$alphaT_minus))
  expect_true(!is.null(out_simp_fuzzy$diagnostics$denominator))
  expect_true(!is.null(out_simp_fuzzy$bootstrap$e2_mat))
})

test_that("r3d() runs for frechet (sharp) with no errors", {
  set.seed(104)
  test_data <- create_test_data(n = 70, sample_size = 30, fuzzy = FALSE)
  out_frech <- r3d(X = test_data$x, Y_list = test_data$y_list, method = "frechet", p = 1, boot = FALSE)
  
  expect_s3_class(out_frech, "r3d")
  expect_equal(out_frech$method, "frechet")
  expect_length(out_frech$bandwidths$h_star_num, 1)  # Assuming bandwidths is a list
  if (length(out_frech$int_minus) > 1) {
    expect_true(all(diff(out_frech$int_minus) >= -1e-10))
  }
})

test_that("r3d() runs for frechet (fuzzy) with no errors", {
  set.seed(105)
  test_data <- create_test_data(n = 60, sample_size = 50, fuzzy = TRUE)
  out_frech_fuzzy <- r3d(X = test_data$x, Y_list = test_data$y_list, T = test_data$t, fuzzy = TRUE, method = "frechet", p = 1)
  
  expect_s3_class(out_frech_fuzzy, "r3d")
  expect_true(out_frech_fuzzy$fuzzy)
  if (length(out_frech_fuzzy$int_plus) > 1) {
    expect_true(all(diff(out_frech_fuzzy$int_plus) >= -1e-10))
  }
})

################################################################################
# 3) Test bootstrap (boot=TRUE) with method='simple', check we have boot_out
################################################################################

test_that("r3d() boot=TRUE yields boot_out with confidence bands & tests (sharp)", {
  set.seed(106)
  test_data <- create_test_data(n = 40, sample_size = 20, fuzzy = FALSE)
  out_boot <- r3d(X = test_data$x, Y_list = test_data$y_list, method = "simple", p = 1,
                  boot = TRUE, boot_reps = 10, test = "nullity", alpha = 0.2)
  
  expect_s3_class(out_boot, "r3d")
  expect_true("boot_out" %in% names(out_boot))
  expect_true("boot_out" %in% names(out_boot$bootstrap))
  expect_identical(out_boot$boot_out, out_boot$bootstrap$boot_out)
  bo <- out_boot$boot_out
  expect_true(all(c("cb_lower", "cb_upper", "test_stat", "test_crit_val", "p_value") %in% names(bo)))
  expect_equal(length(bo$cb_lower), length(out_boot$q_grid))
  expect_equal(length(bo$cb_upper), length(out_boot$q_grid))
  expect_equal(dim(bo$boot_taus), c(length(out_boot$q_grid), 10))
  expect_true(all(bo$cb_upper >= out_boot$tau, na.rm = TRUE))
  expect_true(all(bo$cb_lower <= out_boot$tau, na.rm = TRUE))
})

test_that("r3d() boot=TRUE yields boot_out with confidence bands & tests (fuzzy)", {
  set.seed(106)
  test_data <- create_test_data(n = 40, sample_size = 20, fuzzy = TRUE)
  out_boot_fuzzy <- r3d(X = test_data$x, Y_list = test_data$y_list, T = test_data$t, fuzzy = TRUE, 
                        method = "simple", p = 1, boot = TRUE, boot_reps = 10, test = "nullity", alpha = 0.2)
  
  expect_s3_class(out_boot_fuzzy, "r3d")
  expect_true("boot_out" %in% names(out_boot_fuzzy))
  expect_true("boot_out" %in% names(out_boot_fuzzy$bootstrap))
  expect_identical(out_boot_fuzzy$boot_out, out_boot_fuzzy$bootstrap$boot_out)
  bo <- out_boot_fuzzy$boot_out
  expect_true(all(c("cb_lower", "cb_upper", "test_stat", "test_crit_val", "p_value") %in% names(bo)))
  expect_equal(length(bo$cb_lower), length(out_boot_fuzzy$q_grid))
  expect_equal(length(bo$cb_upper), length(out_boot_fuzzy$q_grid))
  expect_equal(dim(bo$boot_taus), c(length(out_boot_fuzzy$q_grid), 10))
  expect_true(all(bo$cb_upper >= out_boot_fuzzy$tau, na.rm = TRUE))
  expect_true(all(bo$cb_lower <= out_boot_fuzzy$tau, na.rm = TRUE))
})

test_that("r3d() with boot=TRUE and test='homogeneity' works properly", {
  set.seed(1066)
  hetero_data <- create_hetero_effect_data(n = 60)
  q_grid <- c(0.1, 0.3, 0.5, 0.7, 0.9)
  out_test <- r3d(X = hetero_data$x, Y_list = hetero_data$y_list, cutoff = 0, 
                  method = "simple", p = 1, q_grid = q_grid,
                  boot = TRUE, boot_reps = 20, test = "homogeneity")
  
  expect_true(!is.na(out_test$boot_out$test_stat))
  expect_true(!is.na(out_test$boot_out$p_value))
  expect_true(out_test$boot_out$test_stat > 0)
})

test_that("r3d_bootstrap() can be called directly with r3d object", {
  set.seed(107)
  test_data <- create_test_data(n = 40, sample_size = 20, fuzzy = FALSE)
  r3d_obj <- r3d(X = test_data$x, Y_list = test_data$y_list, method = "simple", p = 1, boot = FALSE)
  bo <- r3d_bootstrap(object = r3d_obj, X = test_data$x, Y_list = test_data$y_list, 
                      B = 5, alpha = 0.1, test = "homogeneity", cores = 1)
  
  expect_true(all(c("cb_lower", "cb_upper", "p_value") %in% names(bo)))
  expect_equal(length(bo$cb_lower), length(r3d_obj$q_grid))
  expect_true(!is.na(bo$p_value))
})

################################################################################
# 4) Scenario-based test with random distributions
################################################################################

delta_mu <- 2
delta_sigma <- 0.5
base_mu_below <- 5
slope_mu_below <- 0.5
base_sigma_below <- 1
slope_sigma_below <- 0.2
c_cutoff <- 0

simulate_data_scenario1 <- function(N, n_obs) {
  x <- runif(N, -1, 1)
  y <- vector("list", N)
  mu_at_c <- base_mu_below + slope_mu_below * c_cutoff
  sigma_at_c <- base_sigma_below + slope_sigma_below * c_cutoff
  for (i in seq_len(N)) {
    if (x[i] < c_cutoff) {
      mu <- rnorm(1, mean = base_mu_below + slope_mu_below * x[i], sd = 1)
      sigma <- abs(rnorm(1, mean = base_sigma_below + slope_sigma_below * x[i], sd = 0.5))
    } else {
      mu <- rnorm(1, mean = mu_at_c + delta_mu, sd = 1)
      sigma <- abs(rnorm(1, mean = sigma_at_c + delta_sigma, sd = 0.5))
    }
    y[[i]] <- rnorm(n_obs, mean = mu, sd = sigma)
  }
  list(x = x, y = y)
}

true_treatment_effect_scenario1 <- function(q_levels) {
  mu_at_c <- base_mu_below + slope_mu_below * c_cutoff
  sigma_at_c <- base_sigma_below + slope_sigma_below * c_cutoff
  mu_below <- mu_at_c
  sigma_below <- sigma_at_c
  mu_above <- mu_below + delta_mu
  sigma_above <- sigma_below + delta_sigma
  q_below <- qnorm(q_levels, mean = mu_below, sd = sigma_below)
  q_above <- qnorm(q_levels, mean = mu_above, sd = sigma_above)
  q_above - q_below
}

test_that("Scenario 1 distribution test => simple & frechet have finite bias", {
  set.seed(108)
  n_rep <- 5
  N <- 80
  n_obs <- 30
  q_levels <- seq(0.01, 0.9, by = 0.1)
  true_te <- true_treatment_effect_scenario1(q_levels)
  
  results_simp <- list()
  results_frech <- list()
  for (r in seq_len(n_rep)) {
    dat <- simulate_data_scenario1(N, n_obs)
    out_simp <- r3d(X = dat$x, Y_list = dat$y, cutoff = c_cutoff, 
                    method = "simple", p = 1, q_grid = q_levels, boot = FALSE)
    out_frech <- r3d(X = dat$x, Y_list = dat$y, cutoff = c_cutoff,
                     method = "frechet", p = 1, q_grid = q_levels, boot = FALSE)
    results_simp[[r]] <- out_simp$tau
    results_frech[[r]] <- out_frech$tau
  }
  simp_mat <- do.call(rbind, results_simp)
  frech_mat <- do.call(rbind, results_frech)
  
  avg_bias_simp <- mean(rowMeans(simp_mat - matrix(true_te, nrow = n_rep, ncol = length(q_levels), byrow = TRUE)), na.rm = TRUE)
  avg_bias_frech <- mean(rowMeans(frech_mat - matrix(true_te, nrow = n_rep, ncol = length(q_levels), byrow = TRUE)), na.rm = TRUE)
  
  expect_lt(abs(avg_bias_simp), 2)
  expect_lt(abs(avg_bias_frech), 2)
})

test_that("Known treatment effect is recovered by both methods (for large enough data)", {
  set.seed(1088)
  test_data <- create_test_data(n = 1000, sample_size=1000, fuzzy = FALSE)
  q_grid <- seq(0.1, 0.9, by = 0.1)
  
  out_simp <- r3d(X = test_data$x, Y_list = test_data$y_list, cutoff = 0, 
                  method = "simple", p = 1, q_grid = q_grid, boot = FALSE)
  out_frech <- r3d(X = test_data$x, Y_list = test_data$y_list, cutoff = 0, 
                   method = "frechet", p = 1, q_grid = q_grid, boot = FALSE)
  
  expect_true(mean(abs(out_simp$tau - test_data$true_effect)) < 0.5)
  expect_true(mean(abs(out_frech$tau - test_data$true_effect)) < 0.5)
})

################################################################################
# 5) Test edge cases and error handling
################################################################################

test_that("r3d handles very small samples with error", {
  x <- c(-0.5, 0.5, -0.2, 0.2)
  y_list <- list(rnorm(5, 1), rnorm(5, 3), rnorm(5, 1.5), rnorm(5, 2.5))
  expect_warning(
    r3d(X = x, Y_list = y_list, cutoff = 0, method = "simple", p = 1)
  )
})

test_that("r3d errors correctly when fuzzy=TRUE but T=NULL", {
  set.seed(110)
  test_data <- create_test_data(n = 20, sample_size = 10, fuzzy = FALSE)
  expect_error(
    r3d(X = test_data$x, Y_list = test_data$y_list, cutoff = 0, method = "simple", fuzzy = TRUE, T = NULL)
  )
})

test_that("r3d handles empty distributions in Y_list", {
  set.seed(111)
  test_data <- create_test_data(n = 20, sample_size = 10, fuzzy = FALSE)
  y_list <- test_data$y_list
  y_list[[5]] <- numeric(0)
  expect_error(
    result <- r3d(X = test_data$x, Y_list = y_list, cutoff = 0, method = "simple", p = 1)
  )
})

################################################################################
# 6) Test summary.r3d() and plot.r3d() methods
################################################################################
test_that("summary.r3d() and plot.r3d() work properly", {
  skip_on_cran()
  set.seed(111)
  test_data <- create_test_data(n = 40, sample_size = 20, fuzzy = FALSE)
  out <- r3d(X = test_data$x, Y_list = test_data$y_list, cutoff = 0, 
             method = "simple", p = 1,
             q_grid = seq(0.25, 0.75, by = 0.25), 
             boot = TRUE, boot_reps = 5, test = "none")
  
  summ_out <- capture.output(summary(out))
  expect_match(summ_out, "Method:", all = FALSE)
  expect_match(summ_out, "Polynomial order p:", all = FALSE)
  expect_match(summ_out, "Aggregated distributional effects:", all = FALSE)
  
  print_out <- capture.output(print(out))
  expect_match(print_out, "R3D: Regression Discontinuity with Distributional Outcomes", all = FALSE)
  
  pdf(NULL)
  expect_silent(plot(out, main = "Test Plot R3D"))
  dev.off()
})


###############################################################################
# 7) Multiple tests
###############################################################################



test_that("r3d() works with multiple test types", {
  set.seed(2001)
  test_data <- create_test_data(n = 40, sample_size = 20, fuzzy = FALSE)
  
  # Run r3d with both nullity and homogeneity tests
  out_multi_test <- r3d(X = test_data$x, Y_list = test_data$y_list, cutoff = 0, 
                        method = "simple", p = 1, boot = TRUE, boot_reps = 10, 
                        test = c("nullity", "homogeneity"), alpha = 0.2)
  
  # Check that we have test results for both types
  expect_true(!is.null(out_multi_test$boot_out$test_results))
  expect_true("nullity" %in% names(out_multi_test$boot_out$test_results))
  expect_true("homogeneity" %in% names(out_multi_test$boot_out$test_results))
  
  # Check that each test type has valid results
  for (test_type in c("nullity", "homogeneity")) {
    test_results <- out_multi_test$boot_out$test_results[[test_type]]
    expect_true(length(test_results) > 0)
    
    # Get the first range result
    first_range <- test_results[[1]]
    
    # Check that it has the expected components
    expect_true(all(c("test_stat", "test_crit_val", "p_value") %in% names(first_range)))
    expect_true(is.numeric(first_range$test_stat))
    expect_true(is.numeric(first_range$test_crit_val))
    expect_true(is.numeric(first_range$p_value))
    expect_true(first_range$p_value >= 0 && first_range$p_value <= 1)
  }
})
test_that("r3d() works with test_ranges for specific quantile subsets", {
  set.seed(2002)
  test_data <- create_test_data(n = 40, sample_size = 20, fuzzy = FALSE)
  q_grid <- seq(0.1, 0.9, by = 0.1)
  
  # Test on a specific range [0.2, 0.7]
  out_range <- r3d(X = test_data$x, Y_list = test_data$y_list, cutoff = 0, 
                   method = "simple", p = 1, q_grid = q_grid, boot = TRUE, boot_reps = 10,
                   test = "nullity", test_ranges = list(c(0.2, 0.7)), alpha = 0.2)
  
  # Check that test results are for the specified range
  expect_true(!is.null(out_range$boot_out$test_results))
  expect_true("nullity" %in% names(out_range$boot_out$test_results))
  
  range_results <- out_range$boot_out$test_results$nullity
  expect_true(length(range_results) > 0)
  
  # Get the range name (should be something like [0.20, 0.70])
  range_name <- names(range_results)[1]
  expect_match(range_name, "\\[0\\.2.*, 0\\.7.*\\]")
  
  # Test results should be calculated on the specified range
  range_result <- range_results[[range_name]]
  expect_true(all(c("range", "test_stat", "test_crit_val", "p_value") %in% names(range_result)))
  expect_equal(range_result$range[1], 0.2)
  expect_equal(range_result$range[2], 0.7)
})

test_that("r3d() works with multi-point ranges that get expanded into pairs", {
  set.seed(2003)
  test_data <- create_test_data(n = 40, sample_size = 20, fuzzy = FALSE)
  q_grid <- seq(0.1, 0.9, by = 0.1)
  
  # Test with a range specified as c(0.2, 0.5, 0.8)
  # This should result in testing on [0.2, 0.5] and [0.5, 0.8]
  out_multi_range <- r3d(X = test_data$x, Y_list = test_data$y_list, cutoff = 0, 
                         method = "simple", p = 1, q_grid = q_grid, boot = TRUE, boot_reps = 10,
                         test = "homogeneity", test_ranges = list(c(0.2, 0.5, 0.8)), alpha = 0.2)
  
  # Check that test results contain two ranges
  expect_true(!is.null(out_multi_range$boot_out$test_results))
  expect_true("homogeneity" %in% names(out_multi_range$boot_out$test_results))
  
  range_results <- out_multi_range$boot_out$test_results$homogeneity
  expect_equal(length(range_results), 2)
  
  # Check that the range names match the expected ranges
  range_names <- names(range_results)
  expect_true(any(grepl("\\[0\\.2.*, 0\\.5.*\\]", range_names)))
  expect_true(any(grepl("\\[0\\.5.*, 0\\.8.*\\]", range_names)))
})

test_that("r3d() works with multiple test types and multiple ranges", {
  set.seed(2004)
  test_data <- create_test_data(n = 40, sample_size = 20, fuzzy = FALSE)
  q_grid <- seq(0.1, 0.9, by = 0.1)
  
  # Test with both nullity and homogeneity tests on two different ranges
  out_complex <- r3d(X = test_data$x, Y_list = test_data$y_list, cutoff = 0, 
                     method = "simple", p = 1, q_grid = q_grid, boot = TRUE, boot_reps = 10,
                     test = c("nullity", "homogeneity"), 
                     test_ranges = list(c(0.2, 0.4), c(0.6, 0.8)), alpha = 0.2)
  
  # Check that test results contain both test types
  expect_true(!is.null(out_complex$boot_out$test_results))
  expect_true(all(c("nullity", "homogeneity") %in% names(out_complex$boot_out$test_results)))
  
  # Check that each test type has results for both ranges
  for (test_type in c("nullity", "homogeneity")) {
    range_results <- out_complex$boot_out$test_results[[test_type]]
    expect_equal(length(range_results), 2)
    
    # Check that the range names match the expected ranges
    range_names <- names(range_results)
    expect_true(any(grepl("\\[0\\.2.*, 0\\.4.*\\]", range_names)))
    expect_true(any(grepl("\\[0\\.6.*, 0\\.8.*\\]", range_names)))
  }
  
  # There should be a total of 4 test results (2 test types × 2 ranges)
  total_tests <- sum(sapply(out_complex$boot_out$test_results, length))
  expect_equal(total_tests, 4)
})

test_that("r3d() handles invalid test_ranges appropriately", {
  set.seed(2005)
  test_data <- create_test_data(n = 40, sample_size = 20, fuzzy = FALSE)
  q_grid <- seq(0.1, 0.9, by = 0.1)

  # Test with a range outside q_grid
  expect_error(
    r3d(X = test_data$x, Y_list = test_data$y_list, cutoff = 0, 
        method = "simple", p = 1, q_grid = q_grid, boot = TRUE, boot_reps = 10,
        test = "nullity", test_ranges = list(c(0, 0.2)), alpha = 0.2)
  )
  
  # Test with a range containing only one value
  expect_error(
    r3d(X = test_data$x, Y_list = test_data$y_list, cutoff = 0, 
        method = "simple", p = 1, q_grid = q_grid, boot = TRUE, boot_reps = 10,
        test = "nullity", test_ranges = list(c(0.3)), alpha = 0.2)
  )
  
  # Test with a range outside [0,1]
  expect_error(
    r3d(X = test_data$x, Y_list = test_data$y_list, cutoff = 0, 
        method = "simple", p = 1, q_grid = q_grid, boot = TRUE, boot_reps = 10,
        test = "nullity", test_ranges = list(c(-0.1, 1.1)), alpha = 0.2)
  )
})

test_that("summary.r3d() properly displays multiple test results", {
  set.seed(2006)
  test_data <- create_test_data(n = 40, sample_size = 20, fuzzy = FALSE)
  q_grid <- seq(0.1, 0.9, by = 0.1)
  
  out_multi <- r3d(X = test_data$x, Y_list = test_data$y_list, cutoff = 0, 
                   method = "simple", p = 1, q_grid = q_grid, boot = TRUE, boot_reps = 10,
                   test = c("nullity", "homogeneity"), 
                   test_ranges = list(c(0.2, 0.8)), alpha = 0.2)
  
  # Capture the summary output
  summary_output <- capture.output(summary(out_multi))
  
  # Check for multiple test results in the output
  expect_true(any(grepl("NULLITY TESTS:", summary_output, fixed = TRUE)))
  expect_true(any(grepl("HOMOGENEITY TESTS:", summary_output, fixed = TRUE)))
  expect_true(any(grepl("Range \\[0\\.2", summary_output)))
  
  # Check for test statistics, critical values, and p-values
  expect_true(any(grepl("Test statistic:", summary_output, fixed = TRUE)))
  expect_true(any(grepl("Critical value:", summary_output, fixed = TRUE)))
  expect_true(any(grepl("P-value:", summary_output, fixed = TRUE)))
})

###############################################################################
# 8) Visual validation checks for numeric testing
###############################################################################

test_that("Visual validation with known treatment effects", {
  skip_on_cran()
  set.seed(737)
  
  # Constant-effect data
  test_data <- create_test_data(n = 300, sample_size = 500, fuzzy = FALSE)
  q_grid <- seq(0.1, 0.9, by = 0.1)
  out_constant <- r3d(X = test_data$x, Y_list = test_data$y_list, cutoff = 0, method = "frechet",
                      kernel_fun = "triangular", p = 2, s = 1, q_grid = q_grid,
                      boot = TRUE, boot_reps = 1000, test = "homogeneity")
  expected_constant <- rep(test_data$true_effect, length(q_grid))
  
  # Heterogeneous-effect data
  hetero_data <- create_hetero_effect_data(n = 500, sample_size = 1000)
  out_hetero <- r3d(X = hetero_data$x, Y_list = hetero_data$y_list, cutoff = 0, method = "frechet",
                    kernel_fun = "triangular", p = 2, s = 1, q_grid = q_grid,
                    boot = TRUE, boot_reps = 1000, test = "homogeneity")
  q_strs <- sub("0+$", "", sprintf("%.2f", q_grid))
  expected_hetero <- as.numeric(hetero_data$true_effects[q_strs])
  
  # Print results
  cat("\n\n==== VISUAL VALIDATION ====\n\n")
  cat("CONSTANT EFFECT MODEL:\n")
  cat("The effect is exactly:", test_data$true_effect, "for all q.\n\n")
  res_const <- data.frame(
    Quantile = q_grid,
    Estimated = round(out_constant$tau, 2),
    Expected = round(expected_constant, 2),
    Bias = round(out_constant$tau - expected_constant, 2),
    LowerCB = round(out_constant$boot_out$cb_lower, 2),
    UpperCB = round(out_constant$boot_out$cb_upper, 2)
  )
  print(head(res_const, 10))
  cat("...\n")
  cat("Homogeneity test p-value:", out_constant$boot_out$p_value, "\n")
  cat("(Should be > 0.05 if effect is truly constant.)\n\n")
  
  cat("HETEROGENEOUS EFFECT MODEL:\n")
  cat("(We used a big replicate to approximate these differences)\n\n")
  res_hetero <- data.frame(
    Quantile = q_grid,
    Estimated = round(out_hetero$tau, 2),
    Expected = round(expected_hetero, 2),
    Bias = round(out_hetero$tau - expected_hetero, 2),
    LowerCB = round(out_hetero$boot_out$cb_lower, 2),
    UpperCB = round(out_hetero$boot_out$cb_upper, 2)
  )
  print(head(res_hetero, 10))
  cat("...\n")
  cat("Homogeneity test p-value:", out_hetero$boot_out$p_value, "\n")
  cat("(Should be < 0.05 since effect varies by quantile.)\n\n")
  
  # Plots
  par(mfrow = c(1, 2))
  plot(out_constant, main = "Constant Treatment Effect (Frechet)", col = "blue", lwd = 2, ylim = c(0, 4))
  abline(h = test_data$true_effect, col = "red", lty = 2, lwd = 2)
  legend("topright", c("Estimated", "True (3)"), col = c("blue", "red"), lty = c(1, 2), lwd = 2)
  
  plot(out_hetero, main = "Heterogeneous Treatment Effect (Frechet)", col = "blue", lwd = 2)
  lines(q_grid, expected_hetero, col = "red", lty = 2, lwd = 2)
  legend("topright", c("Estimated", "Approx. True"), col = c("blue", "red"), lty = c(1, 2), lwd = 2)
  
  expect_true(TRUE)
})


###############################################################################
# 9) Gini coefficient tests
###############################################################################


test_that("calculate_gini_from_quantile correctly measures inequality", {
  # Perfect equality (constant quantile function)
  equal_quantiles <- seq(0.1, 0.9, by = 0.1)
  equal_values <- rep(10, length(equal_quantiles))
  expect_equal(calculate_gini_from_quantile(equal_quantiles, equal_values), 0)
  
  # Perfect inequality (step function at the very end)
  unequal_quantiles <- seq(0, 1, by = 0.1)
  unequal_values <- c(rep(0, 10), 100)
  expect_equal(round(calculate_gini_from_quantile(unequal_quantiles, unequal_values), 2), 0.9)
  
  # Linear quantile function (corresponds to uniform distribution)
  # For a uniform distribution, the Gini coefficient should be 1/3
  uniform_quantiles <- seq(0, 1, by = 0.01)
  uniform_values <- uniform_quantiles * 100  # Q(p) = 100p for uniform on [0,100]
  expect_equal(round(calculate_gini_from_quantile(uniform_quantiles, uniform_values), 2), 0.33)
  
  # Handle negative values
  negative_quantiles <- seq(0.1, 0.9, by = 0.1)
  negative_values <- c(-50, -40, -30, -20, -10, 0, 10, 20, 30)
  expect_true(!is.na(calculate_gini_from_quantile(negative_quantiles, negative_values)))
  
  # Handle empty or insufficient data
  expect_true(is.na(calculate_gini_from_quantile(c(), c())))
  expect_true(is.na(calculate_gini_from_quantile(0.5, 100)))
})

test_that("r3d works with gini test using quantile functions", {
  set.seed(3001)
  
  # Create test data with different distributions above/below cutoff
  n <- 100
  X <- runif(n, -1, 1)
  
  # Create distributions with different inequality levels
  Y_list <- lapply(1:n, function(i) {
    if (X[i] < 0) {
      # More equal distribution below cutoff
      rnorm(50, mean = 5, sd = 1)
    } else {
      # More unequal distribution above cutoff (mixture)
      c(rnorm(25, mean = 3, sd = 0.5), 
        rnorm(25, mean = 8, sd = 1.5))
    }
  })
  
  # Run r3d with Gini test
  out_gini <- r3d(X = X, Y_list = Y_list, cutoff = 0, 
                  method = "simple", p = 1, boot = TRUE, boot_reps = 20, 
                  test = "gini", alpha = 0.1)
  
  # Check results structure
  expect_true(!is.null(out_gini$boot_out$test_results))
  expect_true("gini" %in% names(out_gini$boot_out$test_results))
  
  # Check Gini test results format
  gini_results <- out_gini$boot_out$test_results$gini
  expect_true(length(gini_results) > 0)
  
  # Get the result (should be under "full_sample")
  gini_result <- gini_results[["full_sample"]]
  
  # Check that it has the expected components
  expect_true(all(c("gini_above", "gini_below", "gini_diff", 
                    "test_stat", "test_crit_val", "p_value", 
                    "bootstrap_diffs") %in% names(gini_result)))
  
  # Both Gini coefficients should be between 0 and 1
  expect_true(gini_result$gini_above >= 0 && gini_result$gini_above <= 1)
  expect_true(gini_result$gini_below >= 0 && gini_result$gini_below <= 1)
  
  # The bootstrap distribution should have the right length
  expect_equal(length(gini_result$bootstrap_diffs), 20)
  
  # Check that the Gini coefficients are different - distributions were created to be different
  expect_true(abs(gini_result$gini_diff) > 0.05)
})

test_that("r3d works with multiple tests including gini", {
  set.seed(3002)
  n <- 80
  X <- runif(n, -1, 1)
  
  # Create distributions with both different means and different inequality
  Y_list <- lapply(1:n, function(i) {
    if (X[i] < 0) {
      # Lower mean, more equal
      rnorm(40, mean = 5, sd = 1)
    } else {
      # Higher mean, more unequal
      c(rnorm(20, mean = 6, sd = 0.8), 
        rnorm(20, mean = 9, sd = 2))
    }
  })
  
  # Run r3d with multiple tests
  out_multi <- r3d(X = X, Y_list = Y_list, cutoff = 0, 
                   method = "simple", p = 1, boot = TRUE, boot_reps = 15, 
                   test = c("nullity", "homogeneity", "gini"), alpha = 0.1)
  
  # Check results structure
  expect_true(!is.null(out_multi$boot_out$test_results))
  expect_true(all(c("nullity", "homogeneity", "gini") %in% names(out_multi$boot_out$test_results)))
  
  # Capture the summary output
  summary_output <- capture.output(summary(out_multi))
  
  # Check for test results in the output
  expect_true(any(grepl("NULLITY TESTS:", summary_output, fixed = TRUE)))
  expect_true(any(grepl("HOMOGENEITY TESTS:", summary_output, fixed = TRUE)))
  expect_true(any(grepl("GINI TESTS:", summary_output, fixed = TRUE)))
  
  # Check for Gini-specific output
  expect_true(any(grepl("Gini coefficient above cutoff:", summary_output, fixed = TRUE)))
  expect_true(any(grepl("Gini coefficient below cutoff:", summary_output, fixed = TRUE)))
  expect_true(any(grepl("Difference in Gini coefficients:", summary_output, fixed = TRUE)))
})