# Aggregate gridMET data 
Exploring how windspeed might vary by census tract and race. Includes code for downloading gridMET variables. The purpose of this code is to compute the population weighted yearly means for a gridMET variable by race categories specified in the 5 year American Census Community Survey (ACS). 

## Contact 
**Nicole Keeney**<br>
UC Berkeley School of Public Health, Department of Environmental Health Sciences<br>
nicolejkeeney@gmail.com

## Notes on the code 
Recently, I've been working with GridMET data, which provides high resolution rasters for several relevant climate variables. Variable abbreviations can be viewed [here](http://www.climatologylab.org/wget-gridmet.html). So far, I've written the code to work with wind speed at 10m (vs), wind direction at 10m (th), and precipitation (pr).<br><br>Information on the scripts in the repository: 
  1) `download_gridMET.R`
     * Downloads daily gridMET data from data stored on University of Idaho's servers (https://www.northwestknowledge.net/metdata/data/). User needs to specify a date range and valid gridMET variables. 
     * Will create a directory "data" and download the data by variable into folders within the data folder corresponding to the variable name.
  3) `agg_gridmet_by_race.R`
     * Computes population weighted yearly means for a gridMET variable by race categories specified in the 5 year American Census Community Survey (ACS). 
     * Requires that the user has already downloaded the gridMET data and the CA census tract shapefile into the correct folders, and relies on the tidycensus API to get ACS data. 
     * Allows the user to chose between running in serial or parallel; the script is currently slightly faster running in serial, but adding complexity to the code may make parallel computation a faster option. Loading the ACS data before running the code would likely speed things up for both serial and parallel. 