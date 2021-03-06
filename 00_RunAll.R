##### Load required packages for all scripts --------------------------------------------------------------

# Load packages in this order
library(minpack.lm)
library(MASS)
library(tidyverse)
library(SuppDists)
library(sqldf)
library(lme4)
library(bbmle)
library(truncnorm)
library(grid)
library(gridBase)
library(corrplot)
library(mgcv)
library(popbio)
library(bbmle)





##### Run scripts that do not change between the two scenarios --------------------------------------------

# This will take several minutes; be patient

# "01_SeedVelocities"
# Calculate terminal velocities of seeds and fit to distributions
source("https://raw.githubusercontent.com/TrevorHD/LTEncroachment/master/01_SeedVelocities.R")

# "02_WindSpeeds"
# Load in wind speeds and fit to distributions
source("https://raw.githubusercontent.com/TrevorHD/LTEncroachment/master/02_WindSpeeds.R")

# "03_Dispersal"
# Construct dispersal kernel functions for seeds
source("https://raw.githubusercontent.com/TrevorHD/LTEncroachment/master/03_Dispersal.R")

# "04_CDataPrep"
# Tidy up demography data before creating demography models
source("https://raw.githubusercontent.com/TrevorHD/LTEncroachment/master/04_CDataPrep.R")

# "05_CDataAnalysis_NS.R"
# Create demography models for use in SIPM
source("https://raw.githubusercontent.com/TrevorHD/LTEncroachment/master/05_CDataAnalysis_NS.R")





##### Set up bootstrapping for wavespeeds -----------------------------------------------------------------

# Should bootstrapping occur?
# If not, the model will be run once using full data sets
boot.on <- FALSE

# Determine resampling proportion; that is, the proportion of individuals selected each interation
# Should be in the interval (0, 1), exclusive
# Warning: setting this number very low may adversely affect model behaviour
boot.prop <- 0.80

# Set number of bootstrap iterations
# Please note: one iteration takes a long time (~1 hour), so choose this number wisely
# Ignore this if boot.on = FALSE
boot.num <- 2

# Create empty vectors to populate with wavespeeds for normal and higher survival scenarios
boot.cv1 <- c()
boot.cv2 <- c()





##### Wavespeeds and population growth for normal survival scenario ---------------------------------------

# This takes ~1 hour per bootstrap replicate; be patient
# Note: if boot.on = TRUE, then bootstrapping will not occur and full data will be used

# Override bootstrap replicate number if bootstrapping is turned off
if(boot.on == FALSE){
  boot.num <- 1}

# Begin bootstrapping
time.start <- Sys.time()
for(i in 1:boot.num){
  
  # "00_BootRes"
  # Run resampling subroutine for wind speeds, terminal velocities, and demography
  source("https://raw.githubusercontent.com/TrevorHD/LTEncroachment/master/06_BootRes.R")
  
  # "06_SIPM"
  # Spatial integral projection setting up functions to calculate wavespeeds
  source("https://raw.githubusercontent.com/TrevorHD/LTEncroachment/master/07_SIPM.R")
  
  # Wavespeeds as function of s; growth as function of density
  c.values <- Wavespeed(200)
  
  # Calculate minimum wavespeed
  c.min <- min(c.values)
  
  # Append wavespeed to bootstrapped vector of estimated wavespeeds
  boot.cv1 <- append(boot.cv1, c.min)}

# Get procedure time
time.end <- Sys.time()
time.end - time.start
remove(time.start, time.end)

# Remove other unneeded items from the global environment
remove(fitGAU, fitted_all, err, fitted_vals, i, k, n_cuts_dens, new_fitted_vals, new_weights,
       weights, boot.tv.raw, boot.tv.PDF, boot.ws.raw, boot.ws.PDF)





##### Wavespeeds and population growth for higher survival scenario ---------------------------------------

# NOTE: this part will not be used for now, until we get the other scenario working first

# This will take several minutes; be patient

# Begin bootstrapping
time.start <- Sys.time()
for(i in 1:boot.num){
  
  # "00_BootRes"
  # Run resampling subroutine for wind speeds, terminal velocities, and demography
  source("https://raw.githubusercontent.com/TrevorHD/LTEncroachment/master/06_BootRes.R")
  
  # "05_CDataAnalysis_NS"
  # Create demography models for growth, reproduction, survival, etc. under normal circumstances
  # Must run this before 05_CDataAnalysis_BS since it contains all of the demography models
  source("https://raw.githubusercontent.com/TrevorHD/LTEncroachment/master/05_CDataAnalysis_NS.R")
  
  # "05_CDataAnalysis_BS"
  # Replace survival model in 05_CDataAnalysis_NS with higher survival from above-average rainfall
  source("https://raw.githubusercontent.com/TrevorHD/LTEncroachment/master/05_CDataAnalysis_BS.R")
  
  # "06_SIPM"
  # Spatial integral projection model that calculates wavespeeds
  source("https://raw.githubusercontent.com/TrevorHD/LTEncroachment/master/07_SIPM.R")
  
  # Wavespeeds as function of s; growth as function of density
  c.values.2 <- Wavespeed(200)
  lambda.2 <- c()
  for(i in seq(-1.3, max(boot.CData.s$d.stand), length.out = 100)){
    lambda.i <- TransMatrix(n = 100, d = i)
    lambda.2 <- append(lambda.2, Re(eigen(lambda.i$matrix)$values[1]))}
  
  # Calculate minimum wavespeed
  c.min.2 <- min(c.values.2)
  
  # Append wavespeed to bootstrapped vector of estimated wavespeeds
  boot.cv2 <- append(boot.cv2, c.min.2)
  
  # Clean up
  remove(lambda.i, TM, i)}

# Get procedure time
time.end <- Sys.time()
time.end - time.start
remove(time.start, time.end)





##### Generate main figures -------------------------------------------------------------------------------

# "07_MainFigures"
# Generate figures for wavespeeds and population growth, dispersal, and demographic data
source("https://raw.githubusercontent.com/TrevorHD/LTEncroachment/master/08_MainFigures.R")

