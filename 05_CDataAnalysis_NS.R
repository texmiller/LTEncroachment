##### Prepare data for analysis ---------------------------------------------------------------------------

# Script authored by Tom, with some changes from Trevor

# Define inverse logit function for later use
invlogit <- function(x){exp(x)/(1 + exp(x))}

## Create unique transect as interaction of transect and site
LATR_full <- CData %>% 
  mutate( unique.transect = interaction(transect, site))





##### Growth model ----------------------------------------------------------------------------------------

# Prepare a data subset for growth that drops rows missing either t or t1 size data
# Also create log_volume as a new variable because GAM doesn't like functions of variables as variables
LATR_grow <- LATR_full  %>% drop_na(volume_t,volume_t1) %>%
  mutate(log_volume_t = log(volume_t),
         log_volume_t1 = log(volume_t1))

# Create empty list to populate with model results
LATR_gam_models <- list()

# Three candidate models for the mean: size only, size + density, or size, density, and size:density
# Three candidates for variance: size only, size + density, fitted value (all the covariates plus rfx)

# Pilot fits, where sigma depends on initial size only
LATR_gam_models[[1]] <- gam(list(log_volume_t1 ~s(log_volume_t) + s(unique.transect,bs = "re"), ~s(log_volume_t)), 
                            data = LATR_grow, gamma = 1.4, family = gaulss())
LATR_gam_models[[2]] <- gam(list(log_volume_t1 ~s(log_volume_t) + s(weighted.dens) + s(unique.transect, bs = "re"), ~s(log_volume_t)), 
                            data = LATR_grow, gamma = 1.4, family = gaulss())                
LATR_gam_models[[3]] <- gam(list(log_volume_t1 ~s(log_volume_t) + s(weighted.dens) + weighted.dens:log_volume_t + s(unique.transect,bs = "re"), ~s(log_volume_t)), 
                            data = LATR_grow, gamma = 1.4, family = gaulss()) 

# Fits where sigma depends on both initial size and density
LATR_gam_models[[4]] <- gam(list(log_volume_t1 ~s(log_volume_t) + s(unique.transect, bs = "re"), ~s(log_volume_t) + s(weighted.dens)), 
                            data = LATR_grow, gamma = 1.4, family = gaulss())
LATR_gam_models[[5]] <- gam(list(log_volume_t1 ~s(log_volume_t) + s(weighted.dens) + s(unique.transect, bs = "re"), ~s(log_volume_t) + s(weighted.dens)), 
                            data = LATR_grow, gamma = 1.4, family = gaulss())                
LATR_gam_models[[6]] <- gam(list(log_volume_t1 ~s(log_volume_t) + s(weighted.dens) + weighted.dens:log_volume_t + s(unique.transect, bs = "re"), ~s(log_volume_t) + s(weighted.dens)), 
                            data = LATR_grow, gamma = 1.4, family = gaulss()) 

# These models will be iterated to fit sigma as f(fitted value)
LATR_grow$fitted_vals = LATR_grow$log_volume_t 
LATR_gam_models[[7]] <- gam(list(log_volume_t1 ~s(log_volume_t) + s(unique.transect, bs = "re"), ~s(fitted_vals)), 
                            data = LATR_grow, gamma = 1.4, family = gaulss())
LATR_gam_models[[8]] <- gam(list(log_volume_t1 ~s(log_volume_t) + s(weighted.dens) + s(unique.transect, bs = "re"), ~s(fitted_vals)), 
                            data = LATR_grow, gamma = 1.4, family = gaulss())                
LATR_gam_models[[9]] <- gam(list(log_volume_t1 ~s(log_volume_t) + s(weighted.dens) + weighted.dens:log_volume_t + s(unique.transect, bs = "re"), ~s(fitted_vals)), 
                            data = LATR_grow, gamma = 1.4, family = gaulss())  

# Fit sigma as f(fitted value) for models 7-9
# The "weights" here are 1/sigma values; see ?gaulss for details.
for(mod in 7:9){
  fitGAU = LATR_gam_models[[mod]]
  fitted_all = predict(fitGAU, type = "response", data = LATR);                  
  fitted_vals = new_fitted_vals = fitted_all[, 1]; 
  weights = fitted_all[, 2];
  err = 100; k = 0; 
  while(err > 10^(-6)){
    LATR_grow$fitted_vals = new_fitted_vals; 
    fitGAU <- update(fitGAU); 
    fitted_all = predict(fitGAU, type = "response", data = LATR_grow);   
    new_fitted_vals = fitted_all[, 1]; new_weights = fitted_all[, 2];
    err = weights - new_weights; err = sqrt(mean(err^2)); 
    weights = new_weights; 
    k = k + 1; cat(k, err, "\n");}   
  LATR_gam_models[[mod]] =  fitGAU;}

# Collect model AICs into a single table
grow_aic <- AICtab(LATR_gam_models, base = TRUE, sort = FALSE) 

# Model 5 is the winner: mean ~ s(size) + s(density), sd ~ s(size) + s(density)
# Define model 5 as our best Gaussian model
LATR_grow_best <- gam(list(log_volume_t1 ~s(log_volume_t) + s(weighted.dens) + s(unique.transect, bs = "re"), ~s(log_volume_t) + s(weighted.dens)), 
                      data = LATR_grow, gamma = 1.4, family = gaulss())
LATR_grow_fitted_terms <- predict(LATR_grow_best, type = "terms") 
LATR_grow$pred <- predict.gam(LATR_grow_best, newdata = LATR_grow, exclude = "s(unique.transect)")

# Plot of effect of size on future size -- obviously linear
# plot(LATR_grow$log_volume_t, LATR_grow_fitted_terms[, "s(log_volume_t)"]) 

# Plot of effect of density on growth 
# plot(LATR_grow$weighted.dens, LATR_grow_fitted_terms[, "s(weighted.dens)"]) 

# Plots of effect of size and density on sd(future size)
# plot(LATR_grow$log_volume_t, LATR_grow_fitted_terms[, "s.1(log_volume_t)"]) 
# plot(LATR_grow$weighted.dens, LATR_grow_fitted_terms[, "s.1(weighted.dens)"]) 





##### Flowering probability model -------------------------------------------------------------------------

# populate year t of 2017-2018 transition year
# There are no 2018 data but this way we get all four years in the reproduction models
# Do this by creating the 2017-18 data as a stand-alone df then bind rows
LATR_dat_201718 <- LATR_full[LATR_full$year_t == 2016 & LATR_full$survival_t1 == 1, ]

# These are the 2017 survivors; make their year t demography last year's data
LATR_dat_201718$year_t <- 2017
LATR_dat_201718$year_t1 <- 2018
LATR_dat_201718$max.ht_t <- LATR_dat_201718$max.ht_t1
LATR_dat_201718$max.w_t <- LATR_dat_201718$max.w_t1
LATR_dat_201718$volume_t <- LATR_dat_201718$volume_t1
LATR_dat_201718$perp.w_t <- LATR_dat_201718$perp.w_t1
LATR_dat_201718$flowers_t <- LATR_dat_201718$flowers_t1
LATR_dat_201718$fruits_t <- LATR_dat_201718$fruits_t1
LATR_dat_201718$reproductive_fraction_t <- LATR_dat_201718$reproductive_fraction_t1
LATR_dat_201718$total.reproduction_t <- LATR_dat_201718$total.reproduction_t1

# Now set all the t1 data to NA
LATR_dat_201718$max.ht_t1 <- NA
LATR_dat_201718$max.w_t1 <- NA
LATR_dat_201718$volume_t1 <- NA
LATR_dat_201718$perp.w_t1 <- NA
LATR_dat_201718$flowers_t1 <- NA
LATR_dat_201718$fruits_t1 <- NA
LATR_dat_201718$reproductive_fraction_t1 <- NA
LATR_dat_201718$total.reproduction_t1 <- NA

# Bind rows and create log_vol as new variables (easier for GAMs)
LATR_flow_dat <- bind_rows(LATR_full,LATR_dat_201718) %>% 
  select(unique.transect,volume_t,total.reproduction_t,weighted.dens) %>% drop_na()
LATR_flow_dat$log_volume_t <- log(LATR_flow_dat$volume_t)

# Create empty list to populate with model results
LATR_flower <- list()

# Three candidate models for the mean: size only, size + density, or size, density, and size:density
LATR_flower[[1]] <- gam(total.reproduction_t > 0 ~ s(log_volume_t) + s(unique.transect, bs = "re"),
                        data = LATR_flow_dat, gamma = 1.4, family = "binomial")
LATR_flower[[2]] <- gam(total.reproduction_t > 0 ~ s(log_volume_t) + s(weighted.dens) + s(unique.transect, bs = "re"),
                        data = LATR_flow_dat, gamma = 1.4, family = "binomial")
LATR_flower[[3]] <- gam(total.reproduction_t > 0 ~ s(log_volume_t) + s(weighted.dens) + weighted.dens:log_volume_t + s(unique.transect, bs = "re"),
                        data = LATR_flow_dat, gamma = 1.4, family = "binomial")

# Collect model AICs into a single table
flower_aic<-AICtab(LATR_flower, base = TRUE, sort = FALSE)

# Model 3 is the winner: mean ~ s(size) + s(density) + size:density
# Define model 3 as our best 
LATR_flower_best <- gam(total.reproduction_t > 0 ~ s(log_volume_t) + s(weighted.dens) + weighted.dens:log_volume_t + s(unique.transect, bs = "re"),
                        data = LATR_flow_dat, gamma = 1.4, family = "binomial")
LATR_flower_fitted_terms <- predict(LATR_flower_best, type = "terms") 
LATR_flow_dat$pred <- predict.gam(LATR_flower_best, newdata = LATR_flow_dat, exclude = "s(unique.transect)")

# Plot effect of size on pr(flower)
# plot(LATR_flow_dat$log_volume_t, LATR_flower_fitted_terms[, "s(log_volume_t)"]) 

# Plot effect of density on pr(flower)
# plot(LATR_flow_dat$weighted.dens, LATR_flower_fitted_terms[, "s(weighted.dens)"]) 





##### Fruit production model ------------------------------------------------------------------------------

# Create new df with plants that have produced at least one reproductive structure
LATR_fruits_dat <- subset(LATR_flow_dat, total.reproduction_t > 0)

# Create empty list to populate with model results
LATR_fruits <- list()

# Three candidate models for the mean: size only, size + density, or size, density, and size:density
LATR_fruits[[1]] <- gam(total.reproduction_t ~ s(log_volume_t) + s(unique.transect, bs = "re"),
                        data = LATR_fruits_dat, gamma = 1.4, family = "nb")
LATR_fruits[[2]] <- gam(total.reproduction_t ~ s(log_volume_t) + s(weighted.dens) + s(unique.transect, bs = "re"),
                        data = LATR_fruits_dat, gamma = 1.4, family = "nb")
LATR_fruits[[3]] <- gam(total.reproduction_t ~ s(log_volume_t) + s(weighted.dens) + weighted.dens:log_volume_t + s(unique.transect, bs = "re"),
                        data = LATR_fruits_dat, gamma = 1.4, family = "nb")

# Collect model AICs into a single table
fruits_aic <- AICtab(LATR_fruits, base = TRUE, sort = FALSE)

# Model 2 is the winner: mean ~ s(size) + s(density)
# Define model 2 as our best 
LATR_fruits_best <- gam(total.reproduction_t ~ s(log_volume_t) + s(weighted.dens) + s(unique.transect, bs = "re"),
                        data = LATR_fruits_dat, gamma = 1.4, family = "nb")
LATR_fruits_fitted_terms <- predict(LATR_fruits_best, type = "terms") 
LATR_fruits_dat$pred <- predict.gam(LATR_fruits_best, newdata = LATR_fruits_dat, exclude = "s(unique.transect)")

# Plot effect of size on fruits
# plot(LATR_fruits_dat$log_volume_t, LATR_fruits_fitted_terms[, "s(log_volume_t)"]) 

# Plot effect of density on fruits 
# plot(LATR_fruits_dat$weighted.dens, LATR_fruits_fitted_terms[, "s(weighted.dens)"]) 





##### Survival model --------------------------------------------------------------------------------------

# Combine transplants with large shrubs; keep only location info, survival, volume, and density
CData.Transplants %>% 
  select("site", "transect", "actual.window", 
         "spring_survival_t1", "volume_t", "weighted.dens", "transplant") %>% 
  rename("survival_t1" = "spring_survival_t1") %>% 
  mutate(unique.transect = interaction(transect, site)) %>% 
  rbind(select(LATR_full, "site", "transect", "actual.window", 
               "survival_t1", "volume_t", "weighted.dens", "transplant","unique.transect")) %>% 
  mutate(log_volume_t = log(volume_t)) %>% 
  drop_na() -> LATR_surv_dat

# Investigate size overlap between transplant experiment and observational census
hist(log(LATR_surv_dat$volume_t[LATR_surv_dat$transplant == FALSE]), breaks = 25)
hist(log(LATR_surv_dat$volume_t[LATR_surv_dat$transplant == TRUE]), breaks = 10, add = TRUE, col = alpha("gray", 0.5))

# Plot survival against volume, grouped by transplant status
plot(log(LATR_surv_dat$volume_t[LATR_surv_dat$transplant == FALSE]),
     LATR_surv_dat$survival_t1[LATR_surv_dat$transplant == FALSE])
points(log(LATR_surv_dat$volume_t[LATR_surv_dat$transplant == TRUE]),
       LATR_surv_dat$survival_t1[LATR_surv_dat$transplant == TRUE] - 0.025, pch = 2)

# Create empty list to populate with model results
LATR_surv <- list()

# Three candidate models for the mean: size only, size + density, or size, density, and size:density
LATR_surv[[1]] <- gam(survival_t1 ~ s(log_volume_t) + transplant + s(unique.transect, bs = "re"),
                      data = LATR_surv_dat, gamma = 1.4, family = "binomial")
LATR_surv[[2]] <- gam(survival_t1 ~ s(log_volume_t) + s(weighted.dens)  + transplant + s(unique.transect, bs = "re"),
                      data = LATR_surv_dat, gamma = 1.4, family = "binomial")
LATR_surv[[3]] <- gam(survival_t1 ~ s(log_volume_t) + s(weighted.dens) + transplant + weighted.dens:log_volume_t + s(unique.transect, bs = "re"),
                      data = LATR_surv_dat, gamma = 1.4, family = "binomial")

# Collect model AICs into a single table
surv_aic <- AICtab(LATR_surv, base = TRUE, sort = FALSE)

# Model 3 is the winner: mean ~ s(size) + s(density) + size:density
# Define model 3 as our best 
LATR_surv_best <- gam(survival_t1 ~ s(log_volume_t) + s(weighted.dens) + transplant + weighted.dens:log_volume_t + s(unique.transect, bs = "re"),
                      data = LATR_surv_dat, gamma = 1.4, family = "binomial")
LATR_surv_fitted_terms <- predict(LATR_surv_best, type = "terms") 
LATR_surv_dat$pred <- predict.gam(LATR_surv_best, newdata = LATR_surv_dat, exclude = "s(unique.transect)")

# Plot effect of size on pr(survival)
# plot(LATR_surv_dat$log_volume_t, LATR_surv_fitted_terms[, "s(log_volume_t)"]) 

# Plot effect of density on pr(survival)
# plot(LATR_surv_dat$weighted.dens, LATR_surv_fitted_terms[, "s(weighted.dens)"]) 





##### Per-seed recruitment probability model --------------------------------------------------------------

# Create subset df of recruits
LATR_recruits <- LATR_full %>% 
  mutate(unique.transect = interaction(transect, site)) %>% 
  group_by(year_t1, unique.transect, actual.window) %>% 
  filter(seedling_t1 == 1) %>% 
  summarise(recruits = n()) %>% 
  rename(window = actual.window)

# Estimate total seeds produced in each window
# This is computed using the known plant sizes and the fitted flowering and fruiting models
# Note: we assume 6 seeds per fruit
LATR_transects <- Cdata.Transects.Windows %>% 
  mutate(unique.transect = interaction(transect, site),
         log_volume_t = log(volume))
LATR_transects$seeds = ceiling(invlogit(predict.gam(LATR_flower_best,newdata = LATR_transects))* 
                                 6*exp(predict.gam(LATR_fruits_best,newdata = LATR_transects)))
LATR_transects %>% 
  group_by(unique.transect,window) %>% 
  summarise(total_seeds = sum(seeds),
            weighted.dens = unique(weighted.dens)) -> LATR_transects

# Take three copies of this df, assigning each one to a different year and assigning recruits to zero (for now)
LATR_recruitment <- bind_rows(LATR_transects %>% filter(unique.transect == "1.FPS" | unique.transect == "2.FPS" | unique.transect == "3.FPS") %>% 
                                mutate(year_t1 = 2014, recruits = 0), ## only FPS for 2013-2014
                              LATR_transects %>% mutate(year_t1 = 2015, recruits = 0),
                              LATR_transects %>% mutate(year_t1 = 2016, recruits = 0),
                              LATR_transects %>% mutate(year_t1 = 2017, recruits = 0)) %>% 
  left_join(., LATR_recruits, by = c("year_t1", "unique.transect", "window")) %>% 
  mutate(recruits.y = replace_na(recruits.y, 0),
         recruits = pmax(recruits.x, recruits.y, na.rm = T)) %>% 
  drop_na()

# Create empty list to populate with model results
LATR_recruit <- list()

# Two candidate models for the mean: no effect, or size only
LATR_recruit[[1]] <- gam(cbind(recruits,total_seeds - recruits) ~ s(unique.transect, bs = "re"),
                         data = LATR_recruitment, gamma = 1.4, family = "binomial")
LATR_recruit[[2]] <- gam(cbind(recruits,total_seeds - recruits) ~ s(weighted.dens) + s(unique.transect, bs = "re"),
                         data = LATR_recruitment, gamma = 1.4, family = "binomial")

# Collect model AICs into a single table
recruit_aic <- AICtab(LATR_recruit, base = TRUE, sort = FALSE)

# Null model (no effect) seems to be the best model
LATR_recruit_best <- gam(cbind(recruits,total_seeds - recruits) ~ s(unique.transect, bs = "re"),
                         data = LATR_recruitment, gamma = 1.4, family = "binomial")

# Plot null model
# No evidence for density dependence in recruitment, just a really low overall recruitment rate
plot(LATR_recruitment$weighted.dens, LATR_recruitment$recruits/LATR_recruitment$total_seeds)
LATR_recruitment$pred = predict.gam(LATR_recruit_best, newdata = LATR_recruitment, exclude = "s(unique.transect)")
# points(LATR_recruitment$weighted.dens, invlogit(LATR_recruitment$pred), col = "red", pch = ".")

# Just out of curiosity, the density-dependent model is a very close second... what does this look like?
# LATR_recruit_fitted_terms = predict(LATR_recruit[[2]], type = "terms") 

# Plot effect of density on pr(seedling recruitment); negative density dependence
# plot(LATR_recruitment$weighted.dens,LATR_recruit_fitted_terms[, "s(weighted.dens)"])





##### Recruit sizes and integration limits (size bounds) --------------------------------------------------

# Filter out seedlings and get their sizes
# Plot distribution of recruit sizes using hist(LATR_recruit_size$log_volume)
LATR_recruit_size <- LATR_full %>% 
  filter(seedling_t1 == 1) %>% 
  mutate(log_volume = log(volume_t1))

# Create maximum and minimum size bounds for the IPM
LATR_size_bounds <- data.frame(min_size = log(min(LATR_full$volume_t, LATR_full$volume_t1[LATR_full$transplant == FALSE], na.rm = TRUE)),
                               max_size = log(max(LATR_full$volume_t, LATR_full$volume_t1[LATR_full$transplant == FALSE], na.rm = TRUE)))

