library(RPostgres)
library(DBI)
library(dplyr)
library(tidyr)
library(skimr) # for summarising databases
library(data.table)
library(mltools) #data.table and mltools are needed for "one_hot" function
library(readr)  #read rds

# 1. Load `medexpressesrd` table from postgres and imputed data `micecomplete_pmm`. 
# 2. Merge to create our 5 datasets. Left join `medexpreesrd` and the first set of imputations, keeping imputed cols from imp1, not `medxpreesrd`. 
# 3. Categorical features get one-hot encoded. 
# 
# - Input: `medexpressesrd` and `micecomplete_pmm` tables from postgres
# - Output: universe.RData  (data ready for modeling)

source(file.path("~","ONC_xgboost","category_variables.R"))

con <- dbConnect(
  RPostgres::Postgres(),
  dbname = '',
  host = '',
  port = '',
  user = '',
  password = ''
)

#Read in data from postgres
medxpreesrd = dbGetQuery(
  con,
  "
  SELECT *
  FROM medxpreesrd
  ")

#Read in 5 sets of imputed data from postgres
imputations_pmm = dbGetQuery(
  con,
  "
  SELECT *, row_number() OVER(PARTITION BY usrds_id) AS impnum
  FROM micecomplete_pmm
  ")

#Left join medexpreesrd and imputations, keeping imputed cols from imputations, not medxpreesrd
universe = left_join(
  medxpreesrd %>%
    select(-c("height", "weight", "bmi", "sercr", "album", "gfr_epi", "heglb", "cdtype")),
  imputations_pmm,
  by = c("usrds_id", "subset")
)

num_vars = setdiff(names(universe) , categoryVars)
continuous_vars = c("height", "weight", "bmi", "sercr", "album", "gfr_epi", "heglb")

num_vars = setdiff(num_vars, continuous_vars)

for (cc in num_vars) {
  universe[,cc]=as.numeric(universe[,cc])
}
for (c in categoryVars) {
  universe[,c]=as.factor(universe[,c])
}

universe=data.table(universe)

# one hot encode categorical features
universe=one_hot(as.data.table(universe), naCols=TRUE, dropUnusedLevels = TRUE)
save(universe, file="universe.RData")
