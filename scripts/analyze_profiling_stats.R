#!/usr/bin/env Rscript

args <- commandArgs(trailingOnly = TRUE)
if (length(args) < 1 || args[1] %in% c("-h", "--help")) {
  cat("Usage: analyze_profiling_stats.R DIR\n")
  cat("\nChecks for statistically significant differences by type and version\n")
  cat("using total runtime and total allocated bytes from .prof headers.\n")
  quit(status = ifelse(length(args) >= 1, 0, 1))
}

dir <- args[1]
if (!dir.exists(dir)) {
  stop(paste("Directory not found:", dir))
}

prof_files <- list.files(dir, pattern = "^cardano-node-.*\\.prof$", full.names = TRUE)
if (length(prof_files) == 0) {
  stop("No .prof files found in the directory.")
}

json_files <- list.files(dir, pattern = "\\.json$", full.names = TRUE)

extract_json_value <- function(text, key) {
  pat <- paste0('"', key, '"\\s*:\\s*"([^"]*)"')
  m <- regexpr(pat, text, perl = TRUE)
  if (m[1] == -1) return(NA_character_)
  match <- regmatches(text, m)
  sub(paste0('.*"', key, '"\\s*:\\s*"([^"]*)".*'), '\\1', match, perl = TRUE)
}

read_json_meta <- function(path) {
  text <- paste(readLines(path, warn = FALSE), collapse = " ")
  container <- extract_json_value(text, "container")
  type_val <- extract_json_value(text, "type")
  ver_val <- extract_json_value(text, "node_version")
  data.frame(container = container, type = type_val, node_version = ver_val, stringsAsFactors = FALSE)
}

meta <- if (length(json_files) > 0) {
  do.call(rbind, lapply(json_files, read_json_meta))
} else {
  data.frame(container = character(), type = character(), node_version = character(), stringsAsFactors = FALSE)
}

meta <- meta[!is.na(meta$container) & meta$container != "", , drop = FALSE]

parse_prof <- function(path) {
  lines <- readLines(path, warn = FALSE)
  tag <- sub("^cardano-node-", "", sub("\\.prof$", "", basename(path)))
  tline_idx <- grep("total time", lines, fixed = TRUE)
  aline_idx <- grep("total alloc", lines, fixed = TRUE)
  total_time <- NA_real_
  total_alloc <- NA_real_
  if (length(tline_idx) > 0) {
    tline <- lines[tline_idx[1]]
    total_time <- as.numeric(sub(".*total time\\s*=\\s*([0-9.]+).*", "\\1", tline))
  }
  if (length(aline_idx) > 0) {
    aline <- lines[aline_idx[1]]
    alloc_str <- sub(".*total alloc\\s*=\\s*([0-9,]+).*", "\\1", aline)
    total_alloc <- as.numeric(gsub(",", "", alloc_str))
  }
  data.frame(tag = tag, total_time = total_time, total_alloc = total_alloc, stringsAsFactors = FALSE)
}

prof <- do.call(rbind, lapply(prof_files, parse_prof))

data <- merge(prof, meta, by.x = "tag", by.y = "container", all.x = TRUE)
if (nrow(data) == 0) {
  stop("No profiling data could be parsed.")
}

data$type[is.na(data$type) | data$type == ""] <- "unknown"
data$node_version[is.na(data$node_version) | data$node_version == ""] <- "unknown"

cat("NOTE: Tests use .prof header totals (total time in seconds, total alloc in bytes).\n")
cat("      Summaries report mean/median/sd/min/max and 95% t-interval for the mean.\n")
cat("      Allocation summaries are shown in GB.\n\n")

summary_stats <- function(x) {
  x <- x[!is.na(x)]
  n <- length(x)
  if (n == 0) {
    return(list(n = 0, mean = NA, median = NA, sd = NA, min = NA, max = NA, ci_low = NA, ci_high = NA))
  }
  m <- mean(x)
  med <- median(x)
  s <- if (n > 1) sd(x) else NA
  mn <- min(x)
  mx <- max(x)
  if (n > 1) {
    se <- s / sqrt(n)
    tcrit <- qt(0.975, df = n - 1)
    ci_low <- m - tcrit * se
    ci_high <- m + tcrit * se
  } else {
    ci_low <- NA
    ci_high <- NA
  }
  list(n = n, mean = m, median = med, sd = s, min = mn, max = mx, ci_low = ci_low, ci_high = ci_high)
}

group_summary_table <- function(df, group_col, response, scale = 1, group_label = "group") {
  groups <- sort(unique(df[[group_col]]))
  rows <- lapply(groups, function(g) {
    vals <- df[df[[group_col]] == g, response] / scale
    s <- summary_stats(vals)
    data.frame(
      group = g,
      n = s$n,
      mean = s$mean,
      median = s$median,
      sd = s$sd,
      min = s$min,
      max = s$max,
      ci_low = s$ci_low,
      ci_high = s$ci_high,
      stringsAsFactors = FALSE
    )
  })
  out <- do.call(rbind, rows)
  names(out)[1] <- group_label
  out
}

print_table <- function(df, title) {
  fmt_num <- function(x) ifelse(is.na(x), "NA", sprintf("%.2f", x))
  df_fmt <- df
  df_fmt$n <- as.character(df$n)
  for (col in setdiff(names(df_fmt), c(names(df_fmt)[1], "n"))) {
    df_fmt[[col]] <- fmt_num(df_fmt[[col]])
  }
  widths <- sapply(names(df_fmt), function(col) max(nchar(col), nchar(df_fmt[[col]]), na.rm = TRUE))
  cat(title, "\n", sep = "")
  header <- paste(mapply(function(col, w) sprintf(paste0("%-", w, "s"), col), names(df_fmt), widths), collapse = "  ")
  cat(header, "\n", sep = "")
  for (i in seq_len(nrow(df_fmt))) {
    row <- paste(mapply(function(col, w) sprintf(paste0("%-", w, "s"), df_fmt[i, col]), names(df_fmt), widths), collapse = "  ")
    cat(row, "\n", sep = "")
  }
  cat("\n")
}

run_kw <- function(df, response, group, label) {
  df <- df[!is.na(df[[response]]) & !is.na(df[[group]]), , drop = FALSE]
  n_groups <- length(unique(df[[group]]))
  if (n_groups < 2) {
    cat(label, ": skipped (need >=2 groups)\n")
    return()
  }
  kw <- kruskal.test(df[[response]] ~ as.factor(df[[group]]), data = df)
  cat(label, sprintf(": p=%.4g\n", kw$p.value))
}

print_table(group_summary_table(data, "type", "total_time", scale = 1, group_label = "type"),
            "Summary by type (total_time, seconds):")
print_table(group_summary_table(data, "type", "total_alloc", scale = 1e9, group_label = "type"),
            "Summary by type (total_alloc, GB):")
print_table(group_summary_table(data, "node_version", "total_time", scale = 1, group_label = "version"),
            "Summary by version (total_time, seconds):")
print_table(group_summary_table(data, "node_version", "total_alloc", scale = 1e9, group_label = "version"),
            "Summary by version (total_alloc, GB):")

run_kw(data, "total_time", "type", "Kruskal-Wallis total_time ~ type")
run_kw(data, "total_alloc", "type", "Kruskal-Wallis total_alloc ~ type")
run_kw(data, "total_time", "node_version", "Kruskal-Wallis total_time ~ version")
run_kw(data, "total_alloc", "node_version", "Kruskal-Wallis total_alloc ~ version")

core <- subset(data, !(type %in% c("txg", "client")))
cat("\nCore-only (excluding txg, client):\n\n")
print_table(group_summary_table(core, "node_version", "total_time", scale = 1, group_label = "version"),
            "Summary by version (total_time, seconds):")
print_table(group_summary_table(core, "node_version", "total_alloc", scale = 1e9, group_label = "version"),
            "Summary by version (total_alloc, GB):")
run_kw(core, "total_time", "node_version", "Kruskal-Wallis total_time ~ version (core)")
run_kw(core, "total_alloc", "node_version", "Kruskal-Wallis total_alloc ~ version (core)")
