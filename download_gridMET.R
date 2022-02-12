## download_gridMET.R 
## Author: Nicole Keeney 
## Date Created: 9/16/2021 
## Modification history: n/a
## Purpose: Download gridMET netcdf files for a list of variables and a time range of interest. Will create a directory "data" and download the data by variable into folders within the data folder corresponding to the variable name. 


# ---------------- Install and load dependencies using pacman ----------------  

package_list <- c("tidyverse") # Common packages available on CRAN
if (!require("pacman")) install.packages("pacman")
pacman::p_load(package_list, character.only=TRUE)


# ---------------- User inputs ----------------  

# Define time range 
start_year <- 2005
end_year <- 2015

# Define variables of interest using appropriate GridMET abbreviations 
# See all available variables and their corresponding abbreviations here: http://www.climatologylab.org/wget-gridmet.html
#vars <- c("pr", "vs", "th") # pr: precipitation; vs: windspeed; th: wind direction
vars <- "th"

# ---------------- Download GridMET data for input time range and variables ----------------  

# Generate filepath strings using variables and years, following filepath conventions from GridMET 
years <- seq(from=start_year, to=end_year, by=1)

# Create data directory if it doesn't already exist
dir.create("data", showWarnings=FALSE)

# Function that downloads gridMET data for a given variable name for a vectors of years 
download_gridMET <- function(var_name, years_vect, showWarnings=TRUE){ 
  print(paste0("Downloading GridMET data for variable ", var_name, " for the following years: ", toString(years_vect)))
  filepaths <- paste0("http://www.northwestknowledge.net/metdata/data/", var_name, "_", years_vect, ".nc") # Filepaths for a given variable over the specified range of years 
  dir.create(paste("data/gridMET", var_name, sep="/"), showWarnings=showWarnings) # Create variable directory in data folder 
  sapply(filepaths, 
           FUN=function(filepath_i, var_name) { 
           destfile <- paste("data", "gridMET", var_name, basename(filepath_i), sep="/") # Define the string name of the do
           download.file(filepath_i, destfile=destfile)
         }, 
         var_name=var_name)
}

# Call the function for each variable in the list vars to download the data! :) 
lapply(vars, FUN=download_gridMET, years_vect=years, showWarnings=FALSE)

