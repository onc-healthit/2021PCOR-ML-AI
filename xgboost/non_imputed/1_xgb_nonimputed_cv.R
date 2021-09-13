library(RPostgres)
library(DBI)
library(xgboost)
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
library(here)
##The previous 8 libraries are needed to run using Simon Coulomb's approach
library(data.table)
library(mltools) #data.table and mltools are needed for "one_hot" function
library(readr)  #read rds

#Run a 5-fold cross_validation xgboost model on the training data 
#(70/30 split into test/validation data) to find the optimal hyperparemeters for xgboost. 

source("../category_variables.R")

# load non imputed data ---------------------------------------------------
load('universe.RData')

depvar = "died_in_90"

trainsubsets = c(0,1,2,3,4,5,6)
#testsubsets = c(7,8,9)

rhscols = setdiff(names(universe), c("usrds_id", "subset", "died_in_90"))

train_onc=universe %>% filter(subset %in% trainsubsets) %>% as.data.frame()
#test_onc=universe %>% filter(subset %in% testsubsets) %>% as.data.frame()
rm(universe)
gc()
cv_folds = rBayesianOptimization::KFold(train_onc[, depvar], # creating 5 fold validation
                                        nfolds= 5,
                                        stratified = TRUE,
                                        seed= 0)

dtrain <-xgb.DMatrix(as.matrix(train_onc[, rhscols]), label = train_onc[, depvar])
#dtest <-xgb.DMatrix(as.matrix(test_onc[, rhscols]), label = test_onc[, depvar])
rm(train_onc)
gc()
# Tune parameters ---------------------------------------------------
obj.fun  <- smoof::makeSingleObjectiveFunction(
  name = "xgb_cv_bayes",
  fn =   function(x){
    set.seed(12345)
    cv <- xgb.cv(params = list(
      booster          = "gbtree",
      scale_pos_weight = sqrt(12),
      eta              = x["eta"],
      max_depth        = x["max_depth"],
      min_child_weight = x["min_child_weight"],
      gamma            = x["gamma"],
      lambda           = x["lambda"],
      alpha            = x["alpha"],
      subsample        = x["subsample"],
      colsample_bytree = x["colsample_bytree"],
      max_bin          = x["max_bin"],
      objective        = 'binary:logistic', 
      eval_metric     = "auc",
      tree_method     = "hist"),
      data=dtrain,
      nrounds = x["nround"], 
      folds =  cv_folds, # this was nfold before
      prediction = FALSE,
      showsd = TRUE,
      early_stopping_rounds = 15,
      verbose = 1)
    
    cv$evaluation_log[, max(test_auc_mean)]
  },
  par.set = makeParamSet(
    makeNumericParam("eta",              lower = 0.001, upper = 0.8),
    makeNumericParam("gamma",            lower = 0,     upper = 9),
    makeNumericParam("lambda",           lower = 1,     upper = 9),
    makeNumericParam("alpha",            lower = 0,     upper = 9),
    makeIntegerParam("max_depth",        lower = 2,      upper = 10),
    makeIntegerParam("min_child_weight", lower = 1,      upper = 5),
    makeIntegerParam("nround",           lower = 10,      upper = 500),
    makeNumericParam("subsample",        lower = 0.2,   upper = 1),
    makeNumericParam("colsample_bytree", lower = 0.3,   upper = 1),
    makeIntegerParam("max_bin",          lower = 255,     upper = 1023)
  ),
  minimize = FALSE
)

des = generateDesign(n=length(getParamSet(obj.fun)$pars)+1, # the number of experiments cannot equal the number of variables therefore to increase computation time, we are adding 1 to the total number of hyperparameters.
                     par.set = getParamSet(obj.fun), 
                     fun = lhs::randomLHS)  ## . If no design is given by the user, mlrMBO will generate a maximin Latin Hypercube Design of size 4 times the number of the black-box function's parameters.

control = makeMBOControl()
control = setMBOControlTermination(control, iters = 100) # number of Bayesian iterations

results = mbo(fun = obj.fun, 
              design = des,  
              control = control, 
              show.info = TRUE)

print(results)

save(results, file = "2021_xgb_cv_results_nonimputed.RData")