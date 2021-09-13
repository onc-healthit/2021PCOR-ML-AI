#########Calc totals###
library(dplyr)
library(tidyr)
library(RPostgres)
library(DBI)
library(stringr)
library(readr)

source_dir = file.path("CreateDataSet")
source(file.path(source_dir, "S0-connectToPostgres.R"))

# calculate totals per subset for summary report

df = dbGetQuery(
  con,
  "
  SELECT *
  FROM patients_medevid_waitlist
  "
)

subsets_totals = df %>%
  select(subset) %>%
  group_by(subset) %>%
  count()

subsets_totals = rename(subsets_totals, c("total_pts"=n))

subsets_male = df %>% 
  filter(sex==1) %>%
  select(sex, subset) %>% 
  group_by(sex, subset) %>% 
  count()
subsets_male <- rename(subsets_male, c("total_males"=n))

subsets_white = df %>%
  filter(race==1) %>%
  select(subset, race) %>%
  group_by(subset,race) %>%
  count()
subsets_white <- rename(subsets_white, c("total_white"=n))


subsets_heme = df %>%
  filter(is.na(heglb)==TRUE) %>%
  select(subset,heglb) %>%
  group_by(heglb, subset) %>%
  count()
subsets_heme <- rename(subsets_heme, c("total_heme_na"=n))


subsets_sercr = df %>%
  filter(is.na(sercr)==TRUE) %>%
  select(subset,sercr) %>%
  group_by(sercr, subset) %>%
  count()
subsets_sercr <- rename(subsets_sercr, c("total_sercr_na"=n))


subsets_album = df %>%
  filter(is.na(album)==TRUE) %>%
  select(subset,album) %>%
  group_by(album, subset) %>%
  count() 
subsets_album <- rename(subsets_album, c("total_album_na"=n))


subsets_outcome = df %>%
  filter(died_in_90==1) %>%
  select(subset,died_in_90) %>%
  group_by(died_in_90,subset) %>%
  count()
subsets_outcome <- rename(subsets_outcome, c("total_died"=n))



dd =  
  left_join(
    subsets_totals,
    subsets_outcome,
    by='subset'
)

dd = left_join(
  dd,
  subsets_male,
  by='subset'
)

dd = left_join(
  dd,
  subsets_white,
  by='subset'
)

dd = left_join(  dd,
  subsets_heme,
  by='subset'
)

dd = left_join(  dd,
  subsets_album,
  by='subset'
)

dd = left_join(  dd,
  subsets_sercr,
  by='subset'
)
write_csv(dd, "partition_totals_rev_method.csv")