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
##The previous 8 libraries are needed to run using Simon Coulomb's approach
library(data.table)
library(mltools) #data.table and mltools are needed for "one_hot" function
library(readr)  #read rds
library(rBayesianOptimization)
library(Matrix)

#This file will run 100 Bayesian models that will result in a new range of hyperparameters.

load("~/universe.RData")
depvar = "died_in_90"

rhscols = setdiff(names(universe), c("usrds_id", "subset", "cdtype"))

trainsubsets = c(0,1,2,3,4,5,6)
#testsubsets = c(7,8,9)

model_results <-list()

for(i in 1:5){ 
  
  train=universe %>% 
    filter(subset %in% trainsubsets, impnum == i) %>% as.data.frame()
  
  cv_folds = rBayesianOptimization::KFold(train[, depvar], # creating 5 fold validation
                                          nfolds= 5,
                                          stratified = TRUE,
                                          seed = 0)
  train[] <- lapply(train, as.numeric) #force to numeric columns
  
  options(na.action='na.pass')
  trainm <- sparse.model.matrix(died_in_90 ~ ., data = train[, rhscols])
  dtrain <- xgb.DMatrix(data = trainm, label=train[, depvar])
  
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
        data = dtrain,
        nrounds = x["nround"], 
        folds =  cv_folds, 
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
  
  #save(results, file = paste0("2021_results_run_1_",i,".RData"))
  
  model_results[[i]] <- results 
}
# model_results[[i]]$x returns the best hyperparameters for model i
save(model_results, file = "2021_xgb_results_imputed_1.RData")