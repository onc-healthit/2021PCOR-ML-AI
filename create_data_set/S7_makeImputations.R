library(stringr)
library(dplyr)
library(magrittr)
library(lubridate)
library(RPostgres)
library(DBI)
library(readxl)
library(mice)

# For each of the variables weight, height, gfr_epi, sercr, album, creates an imputation for missing values	
# - Input: `medxpreesrd`	
# - Output: `micecomplete_pmm`	
# 
# The table `micecomplete_pmm` has 5 rows per usrds_id, for each of the imputed columns.
# There is one row per imputation, hence 5 rows per usrds_id. 
# A modeler who wants to use imputed values would use both `medxpreesrd` and `micecomplete_pmm`, 
# replacing weight, height, bmi, sercr, etc. in `medxpreesrd` with the imputed values in `micecomplete_pmm`. 	


source(file.path("CreateDataSet","S0-connectToPostgres.R"))

create_myEgfr <- 
  function(df, cols = c("race", "sex", "inc_age", "sercr")) {
    
    kappa = ifelse(df$sex == 2, .7, .9)
    alpha = ifelse(df$sex == 2, -.329, -.411)
    beta = -1.209
    mn = ifelse(df$sercr / kappa < 1, df$sercr / kappa, 1)
    mx = ifelse(df$sercr / kappa > 1, df$sercr / kappa, 1)
    coef1 = ifelse(df$sex == 2, 1.018, 1)
    coef2 = ifelse(df$race == 2, 1.159, 1)
    egfr = 141 * (mn ^ alpha) * (mx ^ beta) * (.993 ^ df$inc_age) * coef1 *
      coef2
    df$myEgfr = ifelse(is.infinite(egfr), NA, egfr) 
    #Need this or else above equations might yield "Inf" for some values of egfr
    return(df)
}
writeImputations = function(con, miceimp, varstoimpute, dh, subset) {
  
  #dg contains usrds_id and wasna_gfr_epi
  tblname = "micecomplete_pmm"
  dc = as.data.frame(NULL)
  for (i in 1:5) {
    dcimp = complete(miceimp, i) %>% 
      as.data.frame()
    dcimp$impnum = i
    dcimp = create_myEgfr(dcimp)
    dcimp = dcimp %>% 
      left_join((
        dh %>% 
          select(usrds_id, wasna_gfr_epi)), 
        by = "usrds_id")
    dcimp = dcimp %>% 
      mutate(gfr_epi = ifelse(
                          wasna_gfr_epi & !is.na(myEgfr),
                          myEgfr, 
                          gfr_epi)
        )
    dc = rbind(dc, dcimp[, c("usrds_id", varstoimpute)]) %>% 
      as.data.frame()
  }
  
  dc$subset = subset
  
  if (subset == 0) {
    drop_table_function(con, tblname)
    dbWriteTable(
      con, 
      tblname, 
      dc, 
      append = FALSE, 
      row.names = FALSE
      )
  } else {
    dbWriteTable(
      con,
      tblname,
      dc,
      append = TRUE,
      row.names = FALSE
      )
  }
  return(0)
}
makeImputations <- 
  function(con, subset, bounds, impseed, data_tablename) {
    df = dbGetQuery(
      con, 
      str_glue(
        "SELECT * 
        FROM {data_tablename}
        WHERE subset={subset}"
      ))
    
    #Set out-of-bound values to NA so that they will be imputed
    varstoimpute = names(bounds)[2:length(names(bounds))] #Variables to be imputed...

    varstoimpute = c(
      "height",
      "weight",
      "bmi",
      "sercr",
      "album",
      "gfr_epi",
      "heglb"
      )

    varstouse = c(
      "inc_age",
      "race",
      "sex",
      "hispanic",
      "num_como_nas",
      "num_como_Ns",
      "num_como_Ys",
      "num_como_Us",
      "sercr",
      "height",
      "weight",
      "album",
      "heglb"
    ) 

    dg = df[, c("usrds_id", union(varstoimpute, varstouse))]
    dh = df[, c("usrds_id", "wasna_gfr_epi")]
    dg = dg %>% 
      mutate(
        hispanic = as.factor(hispanic),
        race = as.factor(race),
        sex = ifelse(is.na(sex), 0, sex) %>% 
          as.factor()
    )
    
    imp <- mice(dg, seed = impseed, maxit = 0)
    predictorMatrixDf = imp$predictorMatrix 
    #An entry of 1 means the column variable was used to impute the row variable
    meth = imp$method
    
    #row_imputed indexes the row (variable to be imputed);
    #c indexes the column (variable to use as an independent variable to impute row_imputed)
    for (row_imputed in colnames(predictorMatrixDf)) {
      predictorMatrixDf[,row_imputed ] = 0
    }
    
    for (col_imputed in varstoimpute) {
      for (impute_by in varstouse) {
        if (col_imputed != impute_by)
          predictorMatrixDf[col_imputed, impute_by] = 1
      }
  }
  
  # bmi is arithmetically related to weight and height
  # so it needs to be handled with a separate model
  predictorMatrixDf["bmi", "height"] = 1
  predictorMatrixDf["bmi", "weight"] = 1
  
  for (to_use in c("usrds_id", varstouse)) {
    meth[to_use] = ""
  }
  for (to_impute in varstoimpute) {
    meth[to_impute] = "pmm"
  }
  meth["bmi"] = "~ I(weight/(.01*height)^2)"
  #Model the arithmetic relationship among bmi, weight, and height
  
  miceimp <-
    mice(
      dg,
      m = 5,
      maxit = 20,
      threshold = .99999,
      seed = impseed,
      predictorMatrix = predictorMatrixDf,
      method = meth,
      print =  FALSE
    )
  
  writeImputations(
    con, 
    miceimp, 
    varstoimpute, 
    dh, 
    subset
    )
  return(0)
  
}

# Execute Function --------------------------------------------------------
seeds = c(2397, 3289, 4323, 4732, 691, 2388, 2688, 176, 1521, 461)
source_dir = file.path("CreateDataSet")
bounds = read_excel(file.path(source_dir, "imputation_rules.xlsx"), sheet ="Bounds"
                    ) %>% as.data.frame()
starttime = proc.time()[3]
makeImputations(
                con, 
                subset = 0, 
                bounds, 
                impseed = seeds[1], 
                data_tablename="medxpreesrd"
  )
durationinmins = (proc.time()[3] - starttime) / 60
s = 0
print(str_glue("Finished with subset {s} in {durationinmins}"))


starttime = proc.time()[3]
for (s in 1:9) {
  makeImputations(
    con, 
    subset = s,
    bounds, 
    impseed = seeds[s + 1],
    data_tablename="medxpreesrd"
    )
  durationinmins = (proc.time()[3] - starttime) / 60
  print(str_glue("Finished with subset {s} in {durationinmins}"))
}
durationinsecs = proc.time()[3] - starttime