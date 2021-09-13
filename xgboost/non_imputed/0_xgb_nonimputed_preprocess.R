library(RPostgres)
library(DBI)
library(dplyr)
library(tidyr)
#library(mlrMBO)  # for bayesian optimisation  
library(skimr) # for summarising databases
library(data.table)
library(mltools) #data.table and mltools are needed for "one_hot" function
library(readr)  #read rds

source(file.path("~","ONC_xgboost","category_variables.R"))

con <- dbConnect(
  RPostgres::Postgres(),
  dbname = '',
  host = '',
  port = '',
  user = '',
  password = ''
)

universe=dbGetQuery(
  con,
  "SELECT *
  FROM medxpreesrd")

# data cleaning/preprocessing ---------------------------------------------

# remove variables specific to imputation that are not relevant here
universe=universe %>%  select(-c("wasna_height","wasna_weight",
                                 "wasna_bmi","wasna_sercr","wasna_album",
                                 "wasna_gfr_epi","wasna_heglb",
                                 "cdtype"
))

num_vars = setdiff(names(universe) , categoryVars)

continuous_vars = c("height", "weight", "bmi", "sercr", "album", "gfr_epi", "heglb")

num_vars = setdiff(num_vars, continuous_vars)
for (cc in num_vars) {
  universe[,cc]=as.numeric(universe[,cc])
}

for (c in categoryVars) {
  universe[,c]=as.factor(universe[,c])
}

# one hot encode ----------------------------------------------------------
universe=data.table(universe)
universe=one_hot(as.data.table(universe), naCols=TRUE, dropUnusedLevels = TRUE)
save(universe, file="universe.RData")
