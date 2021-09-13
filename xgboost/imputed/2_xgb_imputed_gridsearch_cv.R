# - this file will run the new range of the 5 best combinations of hyperparametes for each of the models for the imputed datasets. 
# - the "best" single combination of hyperparameters resulting from this script will be feed into 5 individual models for each imputed dataset
#   resulting in 5 predictions will be averaged from each imputed dataset that will be used to compute AUC.
library(pROC)
library(rsample)
library(xgboost)
library(sqldf)
library(dplyr)
library(tidyr)
library(magrittr)
##The following 8 libraries are needed to run using Simon Coulomb's approach
library(smoof)
library(mlrMBO)  # for bayesian optimisation  
library(skimr) # for summarising databases
library(purrr) # to evaluate the loglikelihood of each parameter set in the random grid search
library(DiceKriging)
library(rgenoud)
##The previous 8 libraries are needed to run using Simon Coulomb's approach
library(data.table)
library(mltools) #data.table and mltools are needed for "one_hot" function
library(readr)  #read rds
library(rBayesianOptimization)
library(openxlsx)
library(Matrix)

#import list of categorical variables
source(file.path("~","ONC_xgboost","category_variables.R"))

load("~/universe.RData")
depvar = "died_in_90"

rhscols = setdiff(names(universe), c("usrds_id", "subset", "cdtype"))

trainsubsets = c(0,1,2,3,4,5,6)
#testsubsets = c(7,8,9)


# Creating hyperparameter grid for 25 samples given the new ranges from the 5 baysien models

set.seed(123)
how_many_models <- 25
eta <-              data.frame(eta = runif(how_many_models,min = 0.04852942, max = 0.08619335))
gamma <-            data.frame(gamma = runif(how_many_models,min = 0.766442, max = 6.013658))
lambda <-           data.frame(lambda = runif(how_many_models,min = 5.845102, max = 8.751962))
alpha <-            data.frame(alpha = runif(how_many_models,min = 6.516213, max = 8.719468))
max_depth <-        data.frame(max_depth = sample(6:7, how_many_models, replace=TRUE))
min_child_weight <- data.frame(min_child_weight = sample(1:4, how_many_models, replace=TRUE))
nround <-          data.frame(nround = sample(419:499, how_many_models, replace=TRUE))
subsample <-        data.frame(subsample = runif(how_many_models,min = 0.7314413, max = 0.8471972))
colsample_bytree <- data.frame(colsample_bytree = runif(how_many_models,min = 0.5921707, max = 0.8566342))  
max_bin <-          data.frame(max_bin = sample(529:972, how_many_models, replace=TRUE))

random_grid <-eta %>%
  bind_cols(gamma) %>%
  bind_cols(lambda) %>%
  bind_cols(alpha) %>%
  bind_cols(max_depth) %>%
  bind_cols(min_child_weight) %>%
  bind_cols(nround)  %>% 
  bind_cols(subsample) %>%
  bind_cols(colsample_bytree) %>%
  bind_cols(max_bin) %>%as_tibble()


df.params <- bind_rows(random_grid) %>%
  mutate(rownum = row_number(),
         model = row_number())
list_of_param_sets <- df.params %>% nest(-rownum)

colnames(list_of_param_sets) <- c("model","hyperparamters")

train_full = universe %>% 
  filter(subset <=6 ) %>% as.data.frame()
rm(universe)
gc()

all <-list()

for(i in 1:5){
  
  train_onc=train_full %>% 
    #filter(subset <=6 ) %>%
    filter(impnum == i) %>% as.data.frame()
  
  train_onc = train_onc[order(train_onc$usrds_id),] #We sort the data to make sure an usrsd_id will always end up in the training or validation regardless
  # of which imputed dataset we are using
  
  all_na <- function(x) any(!is.na(x)) #creating function that removes columns containing all NAs
  train_onc <- train_onc %>% select_if(all_na) #removing the columns containing all NAs
  
  train_onc[] <- lapply(train_onc, as.numeric) #force to numeric columns
  
  set.seed(2369)
  tr_te_split <- rsample::initial_split(train_onc, prop = 7/10) #70% for training, 30% for validation/test
  train_onc <- rsample::training(tr_te_split) %>% as.data.frame()
  test_onc  <- rsample::testing(tr_te_split) %>% as.data.frame()
  
  #per https://stackoverflow.com/questions/48805977/r-missing-data-causes-error-with-xgboost-sparse-model-matrix
  options(na.action='na.pass')
  trainm <- sparse.model.matrix(died_in_90 ~ ., data = train_onc[, c(rhscols,"died_in_90")]) 
  dtrain <- xgb.DMatrix(data = trainm, label=train_onc[, depvar])
  
  testm <- sparse.model.matrix(died_in_90 ~ ., data = test_onc[, c(rhscols,"died_in_90")]) 
  dtest <- xgb.DMatrix(data = testm, label=test_onc[, depvar])
  watchlist <- list(train = dtrain, eval = dtest)
  
  random_grid_results <- list_of_param_sets %>% 
    mutate(results = map(hyperparamters, function(x){
      
      message(paste0("model #",       x$model,
                     " eta = ",              x$eta,
                     " max.depth = ",        x$max_depth,
                     " min_child_weigth = ", x$min_child_weight,
                     " subsample = ",        x$subsample,
                     " colsample_bytree = ", x$colsample_bytree,
                     " gamma = ",            x$gamma, 
                     " nrounds = ",          x$nround))
      
      set.seed(12345)
      singleModel <- xgb.train(params = list(
        booster          = "gbtree",
        scale_pos_weight = sqrt(12),
        eta              = x$eta,
        max_depth        = x$max_depth,
        min_child_weight = x$min_child_weight,
        gamma            = x$gamma,
        lambda           = x$lambda,
        alpha            = x$alpha,
        subsample        = x$subsample,
        colsample_bytree = x$colsample_bytree,
        max_bin          = x$max_bin,
        objective        = 'binary:logistic', 
        eval_metric     = "auc"),
        data=dtrain,
        nrounds = x$nround,  
        prediction = FALSE,
        watchlist = watchlist,
        showsd = TRUE,
        early_stopping_rounds = 15,
        verbose = 2)
      
      output <- list(score = predict(singleModel, dtest),
                     id = test_onc$usrds_id
      )
      return(output)
    }))
  
  all[[i]] <- random_grid_results # add the results to a list
}

final_hp_results <- data.frame()

#looping through each set of the 25 hyperparamters to pool 5 scores together to compute auc
for(i in 1:how_many_models){
  
  one <- as.data.frame(data.table::transpose(all[[1]]$results[[i]]))[1,] %>% 
    tidyr::gather(key = "usrds_id", value = "score") %>% 
    mutate(usrds_id = all[[1]]$results[[i]]$id)
  
  two <- as.data.frame(data.table::transpose(all[[2]]$results[[i]]))[1,] %>% 
    tidyr::gather(key = "usrds_id", value = "score") %>% 
    mutate(usrds_id = all[[2]]$results[[i]]$id)
  
  third <- as.data.frame(data.table::transpose(all[[3]]$results[[i]]))[1,] %>% 
    tidyr::gather(key = "usrds_id", value = "score") %>% 
    mutate(usrds_id = all[[3]]$results[[i]]$id)
  
  fourth <- as.data.frame(data.table::transpose(all[[4]]$results[[i]]))[1,] %>%
    tidyr::gather(key = "usrds_id", value = "score") %>%
    mutate(usrds_id = all[[4]]$results[[i]]$id)
  
  fifth <- as.data.frame(data.table::transpose(all[[5]]$results[[i]]))[1,] %>%
    tidyr::gather(key = "usrds_id", value = "score") %>%
    mutate(usrds_id = all[[5]]$results[[i]]$id)
  
  pooling  = one %>% 
    inner_join(two, by = "usrds_id") %>% 
    inner_join(third, by = "usrds_id") %>%
    inner_join(fourth, by = "usrds_id") %>%
    inner_join(fifth, by = "usrds_id")
  
  pooling$averaged  <- apply(pooling[2:ncol(pooling)], 1, mean) #averaging scores
  
  pooling <- left_join(pooling, test_onc %>% select("usrds_id","died_in_90"), by = "usrds_id")
  
  auc <- pROC::auc(pooling$died_in_90, pooling$averaged) #compute AUC
  
  if(i == 21){
    pooling_sample <- pooling[1:5,] #sample to verify it is doing it correctly
    save(pooling_sample,file =  "2021_pooling_sample.RData") 
  }
  
  toAdd <- data.frame(hyper = all[[1]]$hyperparamters[[i]],
                      auc = auc)
  
  final_hp_results <- rbind(final_hp_results,toAdd)
}
save(final_hp_results, file =  "2021_final_hp_results_random_grid_imputed.RData")

openxlsx::write.xlsx(as.data.frame(final_hp_results), file =  "2021_final_hp_results_random_grid_imputed.xlsx",
                     sheetName='Sheet1', row.names=FALSE,showNA = F)  