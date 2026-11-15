# download_data.R
# Downloads the NHANES files used in this project from the CDC website
# into data/raw/. Only needed if data/raw/ is empty.
# Cycles: 2013-2014 (H), 2015-2016 (I), 2017-2018 (J)

cycles <- c(H = "2013", I = "2015", J = "2017")
tables <- c("DEMO", "BMX", "BPX", "GHB", "GLU", "DIQ",
            "TCHOL", "HDL", "SMQ", "PAQ", "MCQ")

dir.create("data/raw", showWarnings = FALSE, recursive = TRUE)

for (s in names(cycles)) {
  for (t in tables) {
    file <- paste0(t, "_", s, ".XPT")
    dest <- file.path("data/raw", file)
    if (file.exists(dest)) next
    url <- paste0("https://wwwn.cdc.gov/Nchs/Data/Nhanes/Public/",
                  cycles[s], "/DataFiles/", t, "_", s, ".xpt")
    message("Downloading ", url)
    download.file(url, dest, mode = "wb")
  }
}
