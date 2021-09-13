library(readr)
library(dplyr)
library(lubridate)
library(haven)
library(stringr)
source('CreateDataSet/S0-connectToPostgres.R')

#For pre-esrd claims before 2011, there is no pdgns_cd. Instead, there is a drg_cd.
#So we need to map drg_cd to pdgns_cd.

#The script `S3a-esrd_claims.R` needs to have been run in order to generate the 
#data used by this script. The in-patient claims ( preesrd5y_ip_clm_inc) have
#both ***drg_cd*** and ****pdgns_cd****. 
#These are used as the source data for mapping ***drg_cd*** to ****pdgns_cd****. 
#We use this to generate the joint
#distributions of drg_cd and pdgns_cd. In generating the pdgns_cd for early pre-esrd claims (i.e., those
#before 2011), we use this joint distribution.
#- Output: table drg_cd_mapping

res = dbGetQuery(
  con,
  "WITH pre_drg_pdgn AS (
                        SELECT drg_cd, pdgns_cd, COUNT(*) AS nmbr 
                        FROM preesrd5y_ip_clm_inc
                        WHERE cdtype='I' 
                        GROUP BY drg_cd, pdgns_cd),
          drg_cd_tbl AS (
                        SELECT drg_cd, pdgns_cd, nmbr, 
                        row_number() OVER (PARTITION BY drg_cd 
                                          ORDER BY nmbr DESC) 
                        FROM pre_drg_pdgn
                        )
  SELECT a.drg_cd, a.pdgns_cd, a.nmbr, a.row_number, SUM(b.nmbr) AS cum 
  FROM drg_cd_tbl a
    INNER JOIN drg_cd_tbl b 
    ON a.drg_cd=b.drg_cd 
    AND a.row_number<=b.row_number 
    GROUP BY a.drg_cd, a.pdgns_cd, a.nmbr, a.row_number 
    ORDER BY a.drg_cd, a.row_number"
)


## --aggregate table by drg_cd
bydrgcd = res %>% 
  group_by(drg_cd) %>%
  dplyr::summarise(
    total = sum(as.numeric(nmbr)))
res = res %>% 
  inner_join(
    bydrgcd,
    by = "drg_cd")
res = res %>% 
  mutate(
        cum0 = as.numeric(cum - nmbr),
        cum = as.numeric(cum),
        lb = cum0 / total,
        ub = cum / total
)
# res=res[with(res,order(drg_cd,ub,decreasing=T))]

drg_cd_mapping = res %>% 
  select(
          drg_cd, 
          pdgns_cd,
          lb, 
          ub)

# df$pdgns_cd=str_pad(df$pdgns_cd,width=7,side="right",pad="0")

drg_tblname = "drg_cd_mapping"
drop_table_function(con, drg_tblname)
dbWriteTable(con,
             drg_tblname,
             drg_cd_mapping,
             append = F,
             row.names = FALSE)