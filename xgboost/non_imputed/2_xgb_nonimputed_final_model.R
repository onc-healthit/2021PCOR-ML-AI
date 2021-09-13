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
library(here)
##The previous 8 libraries are needed to run using Simon Coulomb's approach
library(data.table)
library(mltools) #data.table and mltools are needed for "one_hot" function
library(readr)  #read rds


# load non imputed data ---------------------------------------------------
load("universe.RData")

depvar = "died_in_90"

trainsubsets = c(0,1,2,3,4,5,6)
testsubsets = c(7,8,9)

rhscols = setdiff(names(universe), c("usrds_id", "subset", "died_in_90"))

train_onc=universe %>% filter(subset %in% trainsubsets) %>% as.data.frame()
train_onc = train_onc[order(train_onc$usrds_id),]

test_onc=universe %>% filter(subset %in% testsubsets) %>% as.data.frame()
test_onc = test_onc[order(test_onc$usrds_id),]


rm(universe)
gc()

dtrain <-xgb.DMatrix(as.matrix(train_onc[, rhscols]), label = train_onc[, depvar])
dtest <-xgb.DMatrix(as.matrix(test_onc[, rhscols]), label = test_onc[, depvar])

set.seed(297)

# Cross-validation yields hyperparameters:
#########load the results from step 1 for our best parameters

load("./roc_auc/2021_xgb_cv_results_nonimputed.RData")

xeta= results$x[['eta']]
xgamma= results$x[['gamma']]
xlambda= results$x[['lambda']]
xalpha= results$x[['alpha']]
xmax_depth= results$x[['max_depth']]
xmin_child_weight= results$x[['min_child_weight']]
xnround=results$x[['nround']]
xsubsample= results$x[['subsample']]
xcolsample_bytree= results$x[['colsample_bytree']]
xmax_bin=results$x[['max_bin']]


scenarios = as.data.frame(
  rbind(
    
    c(xalpha, xcolsample_bytree, xeta, xgamma, xlambda, xmax_bin, xmax_depth, xmin_child_weight, xnround, xsubsample)
    
  ))
names(scenarios)=c("alpha","colsample_bytree","eta","gamma","lambda","max_bin","max_depth",
                   "min_child_weight","rounds","subsample")

scenarios$inx = 1:dim(scenarios)[1]

watchlist <- list(eval = dtest, train = dtrain)

attr(dtrain, 'label') <- getinfo(dtrain, 'label')
dy = NULL

for (i in scenarios$inx) {
  s = scenarios[scenarios$inx == i, ]
  
  param <-
    list(
      max_depth = s$max_depth,
      eta = s$eta,
      nthread = 16,
      verbosity = 0,
      gamma = s$gamma,
      lambda = s$lambda,
      alpha = s$alpha,
      maximize = TRUE,
      tree_method = "hist",
      max_bin = s$max_bin,
      min_child_weight=s$min_child_weight,
      eval_metric = "auc",
      colsample_bytree=s$colsample_bytree,
      subsample=s$subsample,
      scale_pos_weight=sqrt(12),
      objective = "binary:logistic"
    )
  set.seed(297)
  starttime = proc.time()[3]
  fit <-
    xgb.train(
      param,
      dtrain,
      s$rounds,
      # nthread=16,
      watchlist,
      maximize = TRUE,
      early_stopping_rounds = 15,
      verbose = 1
    )
  
  feature_imp = xgb.importance(fit$feature_names,
                               model = fit)
  
  save(feature_imp, file = "./roc_auc/2021_xgb_nonimputed_feature_importance.RData")
  
  endtime = proc.time()[3]
  durationinsecs = (endtime - starttime)
  
  dx = as.data.frame(cbind(predict(fit, newdata = dtest), as.vector(getinfo(dtest, "label"))))
  names(dx)[1:2] = c("score", "y")
  dx$usrds_id = test_onc$usrds_id
  
  write.csv(dx,file="./roc_auc/2021_xgb_nonimputed_y_proba.csv")
  
  openxlsx::write.xlsx(as.data.frame(dx), file =  "./roc_auc/2021_nonimputed_predictions.xlsx",
                       sheetName='Sheet1', row.names=FALSE,showNA = F)  
  
  
  outdata = as.data.frame(seq(0, .99, .01))
  names(outdata) = "bin"
  
  above_thresh = sqldf(
    "select a.bin as threshold, sum(b.y) as tp, count(b.y) as detections
    from outdata a
    left join dx b on a.bin<=b.score
    group by a.bin
    order by a.bin desc"
  )
  
  below_thresh = sqldf(
    "select a.bin as threshold, sum(b.y) as fn, count(b.y) as nondetections
    from outdata a
    left join dx b on a.bin>b.score
    group by a.bin
    order by a.bin desc"
  )
  
  
  perfdata = above_thresh %>% left_join(below_thresh, by = c("threshold"))
  perfdata$tp = replace_na(perfdata$tp, 0)
  perfdata$fn = replace_na(perfdata$fn, 0)
  
  perfdata = perfdata %>% mutate(
    fp = detections - tp,
    tn = nondetections - fn,
    sensitivity = tp / (tp + fn),
    specificity = tn / (fp + tn),
    fpr = 1 - specificity,
    tpr = sensitivity,
    LR = sensitivity / (1 - specificity),
    ppv = tp / detections,
    npv = tn / (tn + fn)
  )
  
  
  perfdata$iter = i
  
  perfdata$durationinsecs = durationinsecs
  
  # pos.scores = dx$score[dx$y == 1]
  # neg.scores = dx$score[dx$y == 0]
  # 
  # #perfdata$auc_tim_test = mean(sample(pos.scores, 7000, replace = T) > sample(neg.scores, 7000, replace = T))
  perfdata$auc_xgb_test = max(fit$evaluation_log$eval_auc)
  perfdata$auc_xgb_train = max(fit$evaluation_log$train_auc)
  
  dy = as.data.frame(rbind(dy, perfdata))
  
  print(paste0("Finished iteration ", i, " auc_tim_test: ", max(perfdata$auc_xgb_test, " Duration ", durationinsecs)))
}
##########
dy = dy %>% mutate(
  accuracy = (tp + tn) / (tp + tn + fp + fn),
  f1_score = 2 * ppv * sensitivity / (ppv + sensitivity)
)
write.csv(dy,file="./roc_auc/2021_xgbResults_nonimputed.csv")
#sink()
