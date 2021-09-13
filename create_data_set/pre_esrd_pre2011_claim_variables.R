#variables for creating the table for pre esrd claims from 2008-2010

filenames_esrd = c("inc2010",
                   "inc2009",
                   "inc2008"
)
####column types #####
columns_esrd_2015 = cols(
  ATTENDING_PHYS = col_double(),
  CLM_AMT = col_double(),
  CLM_TOT = col_double(),
  CVR_DCNT = col_double(),
  DRG_CD = col_double(),
  DIALCRC = col_double(),
  DIALCASH = col_double(),
  DIALSESS = col_double(), 
  DPOADMIN = "c",
  DPOCASH = col_double(),  
  DPODOSE = col_double(),
  DIALREVC = "c",
  DISCSTAT = "c",
  EPODOSE = col_double(),
  EPOCASH = col_double(),  
  EPOADMIN = col_double(),
  HCFASAF = "c",
  HCRIT = col_double(),
  HGB =col_double(),
  masked_CLM_THRU = col_double(),
  masked_CLM_FROM = col_double(),
  OPERATING_PHYS = col_double(),
  OTHER_PHYS = col_double(),
  PER_DIEM = col_double(),
  PROVUSRD = col_double(),
  PRM_PYR = "c",
  randomOffsetInDays = col_double(),
  RXCAT = "c",
  SEQ_KEYC = "c"
)