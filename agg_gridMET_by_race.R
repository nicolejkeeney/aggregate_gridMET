## agg_gridMET_by_race.R
## Author: Nicole Keeney 
## Date Created: 09-16-2021 
## Modification history: 
##  - Added instructions for setting up census API key (02-11-2022)
## 
## Purpose: Compute population weighted yearly means for a gridMET variable by race categories specified in the 5 year American Census Community Survey (ACS)
##
## Notes:
##  - YOU NEED TO DOWNLOAD A CENSUS API KEY IN ORDER TO RUN THIS CODE. Do so here: https://api.census.gov/data/key_signup.html
##  - I find the tidycensus package a bit buggy. If you're getting a bunch of errors, it could be coming from that package. See: https://github.com/walkerke/tidycensus/issues/160
##  - Good resource for info on parallelization in R: https://dept.stat.lsa.umich.edu/~jerrick/courses/stat701/notes/parallel.html


# ---------------- Install and load dependencies using pacman ----------------  

package_list <-c("lubridate","ggplot2","tidycensus","dplyr","sf","raster","tidyverse","ncdf4","stars","parallel","ncmeta") # Common packages available on CRAN
if (!require("pacman")) install.packages("pacman")
pacman::p_load(package_list, character.only=TRUE)


# ---------------- User inputs  ----------------  

var_name <- "pr" # gridMet variable string 
start_year <- 2010
end_year <- 2015
agg_by <- "year" # What temporal scale do you want to aggregate by? Valid inputs: "month" or "year"
parallel <- FALSE # Set FALSE for serial. As of Oct 6, 2021, the script is actually 2x as fast in serial
output_dir <- paste("data/results/pop_weighted_race", var_name, sep="/") # Directory to save results to 


# ---------------- Define functions used in script  ----------------  

read_centralValley_tract <- function(shapefilePath="data/shapefiles/tl_2019_06_tract") {
  # Read in CA census tract shapefile. Restrict to CA central valley. Convert to crs=4326 
  central_valley <- c(Fresno = "019", # County FP codes corresponding to each county in the Central Valley
                      Kern = "029",
                      Kings = "031", 
                      Madera = "039", 
                      Merced = "047", 
                      Mariposa = "043",
                      SanJoaquin = "077", 
                      Stanislaus = "099", 
                      Tulare = "107")   
  ca_tract <- sf::read_sf(shapefilePath) %>% # Read in shapefile 
    dplyr::select(GEOID, COUNTYFP, geometry) %>%  
    dplyr::filter(COUNTYFP  %in% unname(central_valley)) # Just get census tracts in the Central Valley 
  ca_tract$geometry <- sf::st_transform(ca_tract$geometry, crs=4326) # Convert geometry to 4326 CRS
  ca_tract$geom_char <- as.character(ca_tract$geometry) # Create geom_char column with geometry as a character vector. Used in analysis for merging 
  return(ca_tract)
}


get_acs_race_df <- function(year=2019) {
  # Conditions if year is not within 2009-2019
  if (year <= 2008 & year >= 2005) { year <- 2009} # Grab the 2005-2009 ACS 5 year survey
  if (year <= 2004) {stop(paste("Cannot get census data for year",year," using the 5 year ACS survey"))}
  if (year >= 2020) {stop(paste("Cannot get census data for year",year," using the 5 year ACS survey"))}
  
  race_df <- tidycensus::get_acs(geography = 'tract',
                                state = 'CA',
                                county = NULL, 
                                table = 'B02001',
                                year = year, 
                                survey = 'acs5',
                                output = 'wide', 
                                geometry = FALSE, 
                                cache = TRUE) %>% 
    rename(race_total = B02001_001E,
           white = B02001_002E,
           black = B02001_003E,
           amerindian = B02001_004E,
           asian = B02001_005E, 
           pacific_islander = B02001_006E, 
           one_other_race = B02001_007E, 
           two_races1 = B02001_008E, 
           two_races2 = B02001_009E, 
           two_races3 = B02001_010E) %>% 
    mutate(mixed_race = two_races1+two_races2+two_races3) %>% # Sum two or more races 
    dplyr::select(GEOID, race_total, white, black, amerindian, 
                  asian, pacific_islander, one_other_race, 
                  mixed_race) 
  return(race_df)
}
perform_aggregation <- function(year, var_name, ca_tract, acs_df=NA, agg_by="year") {
  cat(year, ": Beginning analysis\n")
  
  # Get acs survey data 
  if (is.na(acs_df)) {acs_df <- get_acs_race_df(year=year)}
  
  # Read in GridMET data 
  cat(year,": Reading in gridmet data\n")
  filepath <- paste0("data/gridMET/",var_name,"/",var_name,"_",year,".nc") # Define filepath 
  if (!file.exists(filepath)) { stop(paste("The file", filepath, "does not exists.\nExitting")) } # Check if files exist. Remove from list if it doesn't exist
  gridmet <- stars::read_ncdf(filepath) %>% # Read in file using stars package
    sf::st_transform(crs=4326) # Add projection to file 
  gridmet_varname <- attr(gridmet, which="name") # Get name of variable
  
  # Aggregate daily gridmet data to census tracts; results in mean daily gridmet data by census tract 
  cat(year,": Aggregating gridmet data by census tract\n")
  gridmet_to_tract <- aggregate(gridmet, by=ca_tract$geometry, FUN=mean, na.rm=TRUE) 
  
  # Aggregate by year or month 
  cat(year,": Aggregating data by", agg_by,"\n")
  if (agg_by=="year") { # Need to covert to num days in that year in order to avoid getting a weird output
    num_days <- as.character(length(stars::st_get_dimension_values(gridmet, "day"))) # Get number of days in year. Use this to aggregate because the function gets confused if there's not exactly 365 days in a year 
    agg_char <- paste(num_days,"days")
  } else { agg_char <- agg_by }
  gridmet_df <- aggregate(gridmet_to_tract, by=agg_char, FUN=mean, na.rm=TRUE)  %>% 
                as.data.frame # Save as dataframe 
  
  # You can't merge on the geometry column for some reason. That's why create a new geometry column geom_char with the geometries as a character vector, then merge on that column instead. 
  # After merging, I drop the sf geometry columns from each dataframe, along with the geom_char column I merged on, and keep the GEOID column (which is used to merge with the census demographic data)
  # The final result dataframe results_comb_df has a time column, gridmet var colum, GEOID, and COUNTYFP
  cat(year,": Merging gridmet aggregation results with census tract GEOID\n")
  gridmet_df$geom_char <- as.character(gridmet_df$geometry)
  results_comb_df <- merge(gridmet_df, ca_tract, by="geom_char")
  results_comb_df <- results_comb_df[ , !(names(results_comb_df) %in% c("geometry.x","geometry.y","geom_char"))]
  
  # Merge with ACS demographic data 
  # Remove rows in data frame that have missing data; this allows me to sum easier in the subsequent steps 
  merged_acs <- merge(na.omit(results_comb_df), acs_df, by="GEOID")
  
  # Compute population weighted mean data for the gridmet var of interest (i.e. compute population weighted wind speed per year)
  # Following method in https://www-sciencedirect-com.libproxy.berkeley.edu/science/article/pii/S001393511731054X
  # Step 1) compute the numerator: census tract gridmet var multiplied by the number of people in each subgroup (i.e. windspeed * num white per census tract)
  # Step 2) sum each column to get a yearly sum for the entire region 
  # Step 3) Divide summed numerator (i.e windspeed * num white) by the total (i.e. total white)
  cat(year,": Computing population weighted",gridmet_varname,"\n")
  col_names <- colnames(acs_df)
  col_names <- col_names[col_names != "GEOID"]
  output_col_names <- paste0("weighted_", col_names)
  
  weighted <- function(pop_col, conc_col) { pop_col*conc_col } # Function to compute the numerator 
  pop_weighted_df <- merged_acs %>% mutate(across(all_of(col_names), ~ weighted(.x, conc_col=merged_acs[[gridmet_varname]]), .names="weighted_{.col}")) %>% 
    dplyr::select(all_of(c("time", gridmet_varname, col_names, output_col_names)))  
  
  pop_weighted_sums <- pop_weighted_df %>% group_by(time=lubridate::floor_date(time, agg_by)) %>% 
    summarize(across(all_of(c(gridmet_varname, col_names, output_col_names)), ~ sum(., is.na(.), 0)))
  
  pop_results <-  pop_weighted_sums[output_col_names] / pop_weighted_sums[col_names]
  pop_results <- data.frame(time=pop_weighted_sums$time, pop_results) # Add year as column 
  
  cat(year,": COMPLETE\n")
  return(pop_results)
}


# ---------------- Run analysis  ----------------  

# Setup
start_time <- Sys.time() # Start timer 
ca_tract <- read_centralValley_tract() # Read central valley shapefile
years <- seq(from=start_year, to=end_year, by=1) # Create vector defining time range

# Print statements indicating years, aggregation period, and gridMET variable
cat("Running analysis for years: ") %>% cat(years) %>% cat("\n")
cat("Aggregation period:", agg_by, "\n")
cat("gridMET variable:", var_name, "\n")


if (parallel==TRUE) { # Run analysis in parallel 
  
  # num_cores = parallel::detectCores() - 1 # Detect number of cores.... using more than 4 cores crashes my computer :/ 
  num_cores = 4 # Set number of cores to use 
  cl <- parallel::makeCluster(num_cores, outfile="") # Make cluster with num_cores
  cat("Running analysis in parallel\nCluster started with", as.character(num_cores), "cores\n")
  
  parallel::clusterEvalQ(cl, {library(stars) # Load libraries into each core
    library(dplyr)
    library(sf)
    library(tidycensus) 
    library(lubridate)})
  
  parallel::clusterExport(cl, c("ca_tract","get_acs_race_df")) # Add variables to each core

  # Run analysis 
  results_df <- parLapply(cl, years, perform_aggregation, var_name=var_name, ca_tract=ca_tract, agg_by=agg_by) %>% bind_rows
  stopCluster(cl)
  cat("ANALYSIS COMPLETE\nStopped cluster\n")
  
} else { # Run in serial
  cat("Running analysis in serial\n")
  results_df <- lapply(years, perform_aggregation, var_name=var_name, ca_tract=ca_tract, agg_by=agg_by) %>% bind_rows
  cat("ANALYSIS COMPLETE\n")
  }

end_time <- Sys.time() # End timer
cat(capture.output(end_time - start_time),"\n") # Print total time elapsed


# ---------------- Save results as csv  ----------------  

# Define output directory and filepath of results csv 
csv_name <- paste0("pop_weighted_",var_name,"_",agg_by,"ly_",as.character(start_year),"-",as.character(end_year),".csv")
filepath_complete <- paste(output_dir, csv_name, sep="/")

# Save file 
dir.create(output_dir, recursive=TRUE, showWarnings=FALSE) # Create directory
write.csv(results_df, filepath_complete) 
cat("Saved output to", filepath_complete, "\n")
cat("END OF SCRIPT")

