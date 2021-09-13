# - the "best" single combination of hyperparameters resulting from step 2 are fed into 5 individual models for each imputed dataset
#   resulting in 5 predictions, then are averaged from each imputed dataset that will be used to compute AUC.
library(pROC)
library(rsample)
library(RPostgres)
library(DBI)
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
library(stringr)

load('~/universe.RData')
depvar = "died_in_90"

rhscols = setdiff(names(universe), c("usrds_id", "subset", "died_in_90"))

trainsubsets = c(0,1,2,3,4,5,6)
testsubsets = c(7,8,9)

set.seed(123)
how_many_models <- 1
eta <-              data.frame(eta = 0.0501135)
gamma <-            data.frame(gamma = 2.937342)
lambda <-           data.frame(lambda = 8.20660)
alpha <-            data.frame(alpha = 7.27306)
max_depth <-        data.frame(max_depth = 7)
min_child_weight <- data.frame(min_child_weight = 2)
nround <-          data.frame(nround = 493)
subsample <-        data.frame(subsample = 0.7513711)
colsample_bytree <- data.frame(colsample_bytree = 0.6611578)  
max_bin <-          data.frame(max_bin = 935)

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

test_full = universe %>% 
  filter(subset > 6 ) %>% as.data.frame()

print(paste("dimensions for train_full:",dim(train_full)))
print(paste("dimensions for test_full:",dim(test_full)))

rm(universe)
gc()

all <-list()

all_features <- list()

for(i in 1:5){
  
  #### training pre-processing
  
  train_onc=train_full %>% 
    #filter(subset <=6 ) %>%
    filter(impnum == i) %>% as.data.frame()
  
  train_onc = train_onc[order(train_onc$usrds_id),] 
  # train_onc = train_onc[1:1000,] #small sample to make sure code runs
  
  rownames(train_onc) <- train_onc$usrds_id #preserving usrds_id as rownames because usrds_id will be removed in next line
  
  train_onc <- train_onc[, c(rhscols,"died_in_90")] #selecting variables 
  
  all_na <- function(x) any(!is.na(x)) #creating function that removes columns containing all NAs
  train_onc <- train_onc %>% select_if(all_na) #removing the columns containing all NAs
  
  train_onc[] <- lapply(train_onc, as.numeric) #force to numeric columns
  
  print(paste("dimensions for train_onc:",dim(train_onc)))
  
  #per https://stackoverflow.com/questions/48805977/r-missing-data-causes-error-with-xgboost-sparse-model-matrix
  options(na.action='na.pass')
  trainm <- sparse.model.matrix(died_in_90 ~ ., data = train_onc) 
  dtrain <- xgb.DMatrix(data = trainm, label=train_onc[, depvar])
  rm(trainm)
  rm(train_onc)
  gc()
  
  #### test pre-processing
  
  test_onc=test_full %>% 
    #filter(subset <=6 ) %>%
    filter(impnum == i) %>% as.data.frame()
  
  test_onc = test_onc[order(test_onc$usrds_id),]
  
  # test_onc = test_onc[1:1000,] #small sample to make sure code runs
  
  test_ids <- test_onc$usrds_id #preserving usrds_id 
  rownames(test_onc) <- test_onc$usrds_id #preserving usrds_id as rownames because usrds_id will be removed in next line
  
  test_onc <- test_onc[, c(rhscols,"died_in_90")] #selecting variables 
  
  test_onc <- test_onc %>% select_if(all_na) #removing the columns containing all NAs
  
  test_onc[] <- lapply(test_onc, as.numeric) #force to numeric columns
  
  print(paste("dimensions for test_onc:",dim(test_onc)))
  
  options(na.action='na.pass')
  testm <- sparse.model.matrix(died_in_90 ~ ., data = test_onc) 
  dtest <- xgb.DMatrix(data = testm, label=test_onc[, depvar])
  rm(testm)
  gc()
  
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
        verbose = 0)
      
      feature_imp <- xgb.importance(singleModel$feature_names,
                                    model = singleModel)
      
      all_features[[i]] <- feature_imp # add feature_imp to list
      
      output <- list(score = predict(singleModel, dtest),
                     id = test_ids
      )
      return(output)
    }))
  
  all[[i]] <- random_grid_results # add the results to a list
  
}
print("xgboost model finished")

final_hp_results_single <- data.frame()

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
  pooling$usrds_id <- as.character(pooling$usrds_id)
  
  test_onc$usrds_id <- as.character(rownames(test_onc))
  
  pooling <- left_join(pooling, test_onc %>% select("usrds_id","died_in_90"), by = "usrds_id")
  
  pooling$predicted <- ifelse(pooling$averaged > 0.5, 1,0)
  
  print("pooling summary after left_join():")
  summary(pooling)
  
  print("conf matrix:")
  table(pooling$predicted, pooling$died_in_90)
  conf_matrix <- table(pooling$predicted, pooling$died_in_90)
  
  save(conf_matrix, file = "2021_conf_matrix.RData")
  
  tp <- conf_matrix[2,2]
  fp <- conf_matrix[2,1]
  fn <- conf_matrix[1,2]
  tn <- conf_matrix[1,1]
  
  sensitivity = tp / (tp + fn)
  specificity = tn / (fp + tn)
  fpr = 1 - specificity
  tpr = sensitivity
  LR = sensitivity / (1 - specificity)
  ppv = tp / (tp + fp)
  npv = tn / (tn + fn)
  f1_score = 2 * ppv * sensitivity / (ppv + sensitivity)
  
  accuracy <- mean(pooling$predicted == pooling$died_in_90)
  
  myplot <- pROC::plot.roc(pooling$died_in_90, pooling$averaged)
  
  save(myplot, file = "2021_myplot_xgb.RData")
  
  toAdd <- data.frame(hyper = all[[1]]$hyperparamters[[i]],
                      auc = myplot$auc,
                      sensitivity = sensitivity,
                      specificity = specificity,
                      fpr = fpr,
                      tpr = tpr,
                      LR = LR,
                      ppv = ppv,
                      npv = npv,
                      f1_score = f1_score
  )
  
  write.csv(pooling, '2021_xgb_pooling_results_final_roc.csv')
  
  final_hp_results_single <- rbind(final_hp_results_single,toAdd)
  
  save(final_hp_results_single, file = "2021_final_hp_results_single_imputed_xgb.RData")
  openxlsx::write.xlsx(as.data.frame(final_hp_results_single), file =  "2021_final_hp_results_single_imputed_xgb.xlsx",
                       sheetName='Sheet1', row.names=FALSE,showNA = F)  
}

print("saving the feature importance")
save(all_features, file = "2021_all_features.RData")

#averging the feature importance
averaged <- all_features %>% reduce(inner_join, by = "Feature") %>% as.data.frame()

rownames(averaged) <- averaged$Feature
averaged = averaged %>% select(contains("Gain"))

averaged$average = as.data.frame(apply(averaged, 1, mean)) #compute average

averaged$feature = rownames(averaged)

save(averaged, file = "2021_averaged_feature_importance_xgb.RData")
#openxlsx::write.xlsx(as.data.frame(averaged), file =  "2021_averaged_single_hyperparameter_xgb.xlsx",
             #        sheetName='Sheet1', row.names=FALSE,showNA = F)